//! 聊天管理器
//!
//! 统一管理所有聊天会话和消息收发。

use super::message::{ChatMessage, ChatError, MessageType, MessageContent};
use super::traits::ChatEvent;
use super::database::manager::{ChatDatabase, SqliteChatDatabase};
use super::database::models::DbMessage;
use crate::node::NodeManager;
use libp2p::PeerId;
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use std::path::PathBuf;
use tokio::sync::{mpsc, RwLock, Mutex as TokioMutex};

/// 最大历史消息条数（内存缓存）
const MAX_HISTORY_SIZE: usize = 1000;

/// 数据库配置
#[derive(Debug, Clone)]
pub struct ChatDatabaseConfig {
    /// 数据库文件路径
    pub db_path: PathBuf,
    /// 是否启用数据库
    pub enabled: bool,
}

impl Default for ChatDatabaseConfig {
    fn default() -> Self {
        // 默认使用应用数据目录
        let mut db_path = dirs::data_local_dir()
            .unwrap_or_else(|| PathBuf::from("."));
        db_path.push("localp2p");
        db_path.push("chat.db");

        Self {
            db_path,
            enabled: true,
        }
    }
}

/// 聊天管理器
///
/// 管理所有聊天会话，负责消息的发送和接收。
/// 支持可选的数据库持久化。
pub struct ChatManager {
    /// 节点管理器（复用，获取已验证节点）
    node_manager: Arc<NodeManager>,
    /// 本地 Peer ID
    local_peer_id: PeerId,
    /// 聊天会话管理（PeerId -> 会话）
    sessions: RwLock<HashMap<PeerId, ChatSession>>,
    /// 消息事件发送器
    event_tx: mpsc::UnboundedSender<ChatEvent>,
    /// 数据库（可选）
    database: TokioMutex<Option<Arc<SqliteChatDatabase>>>,
    /// 数据库配置
    db_config: ChatDatabaseConfig,
}

impl ChatManager {
    /// 创建新的聊天管理器
    pub fn new(node_manager: Arc<NodeManager>, local_peer_id: PeerId) -> (Self, mpsc::UnboundedReceiver<ChatEvent>) {
        Self::with_db_config(node_manager, local_peer_id, ChatDatabaseConfig::default())
    }

    /// 使用数据库配置创建聊天管理器
    pub fn with_db_config(
        node_manager: Arc<NodeManager>,
        local_peer_id: PeerId,
        db_config: ChatDatabaseConfig,
    ) -> (Self, mpsc::UnboundedReceiver<ChatEvent>) {
        let (event_tx, event_rx) = mpsc::unbounded_channel();

        let manager = Self {
            node_manager,
            local_peer_id,
            sessions: RwLock::new(HashMap::new()),
            event_tx,
            database: TokioMutex::new(None),
            db_config,
        };

        (manager, event_rx)
    }

    /// 初始化数据库
    pub async fn initialize_database(&self) -> Result<(), ChatError> {
        if !self.db_config.enabled {
            crate::send_log("INFO", "chat_manager", "数据库功能已禁用".to_string());
            return Ok(());
        }

        let mut db_guard = self.database.lock().await;
        if db_guard.is_some() {
            return Ok(()); // 已初始化
        }

        crate::send_log("INFO", "chat_manager", format!("💬 初始化聊天数据库: {:?}", self.db_config.db_path));

        match SqliteChatDatabase::new(&self.db_config.db_path).await {
            Ok(db) => {
                *db_guard = Some(Arc::new(db));
                crate::send_log("INFO", "chat_manager", "✅ 聊天数据库初始化成功".to_string());
                Ok(())
            }
            Err(e) => {
                crate::send_log("WARN", "chat_manager", format!("⚠️ 聊天数据库初始化失败: {}", e));
                Err(ChatError::Serialization(format!("数据库初始化失败: {}", e)))
            }
        }
    }

    /// 检查数据库是否已初始化
    pub async fn is_database_enabled(&self) -> bool {
        self.db_config.enabled
    }

    /// 发送消息给单个节点
    pub async fn send(&self, target: PeerId, mut message: ChatMessage) -> Result<(), ChatError> {
        // 1. 检查节点是否已验证
        if !self.node_manager.is_node_verified(&target).await {
            return Err(ChatError::NodeNotVerified(target.to_string()));
        }

        // 2. 设置发送者信息
        let message_content = match &mut message {
            ChatMessage::Message(ref mut msg) => {
                msg.sender_peer_id = self.local_peer_id.to_string();
                Some(msg.content.clone())
            }
            ChatMessage::Text(ref mut text) => {
                text.sender_peer_id = self.local_peer_id.to_string();
                None
            }
            ChatMessage::TypingIndicator(ref mut indicator) => {
                indicator.sender_peer_id = self.local_peer_id.to_string();
                None
            }
            ChatMessage::Ack(_) => None,
        };

        // 3. 保存到数据库（如果是消息类型）
        if let Some(db) = self.get_database().await {
            if let (Some(msg_id), Some(content), Some(msg_type)) = (
                message.id().map(|id| id.to_string()),
                message_content,
                Some(message.message_type()),
            ) {
                let peer_id_str = target.to_string();
                let conversation = db.get_or_create_conversation(&peer_id_str, None).await?;

                // 序列化消息内容（包含 msg_type, text, extra 的完整 JSON）
                let content_json = serde_json::to_string(&content)
                    .map_err(|e| ChatError::Serialization(e.to_string()))?;

                // 序列化 extra 字段单独存储（便于查询）
                let extra_json = if !content.extra.is_empty() {
                    Some(serde_json::to_string(&content.extra)
                        .unwrap_or_else(|_| "{}".to_string()))
                } else {
                    None
                };

                let mut db_message = DbMessage::new(
                    conversation.id.clone(),
                    self.local_peer_id.to_string(),
                    msg_type,
                    content_json,
                );

                // 设置 extra 字段
                db_message.extra = extra_json;

                // 插入消息到数据库
                let _ = db.insert_message(db_message).await;

                // 更新会话信息
                let last_msg_text = extract_text_from_content(&content);
                db.update_conversation(
                    &conversation.id,
                    Some(last_msg_text.unwrap_or_else(|| {
                        format!("{:?}", msg_type)
                    })),
                    Some(msg_type),
                    Some(chrono::Utc::now().timestamp_millis()),
                    false, // 发送的消息不增加未读数
                ).await?;
            }
        }

        // 4. 获取或创建会话
        let mut sessions = self.sessions.write().await;
        let session = sessions
            .entry(target)
            .or_insert_with(|| ChatSession::new(target));

        // 5. 编码消息并加入待发送队列
        let _encoded = session.encode_message(message.clone())?;
        session.enqueue_message(message.clone());

        // 6. 发送事件通知
        if let Some(id) = message.id() {
            let _ = self.event_tx.send(ChatEvent::MessageSent {
                to: target,
                message_id: id.to_string(),
            });
        }

        Ok(())
    }

    /// 广播消息给多个节点（一对多）
    pub async fn broadcast(&self, targets: Vec<PeerId>, mut message: ChatMessage) -> Result<(), ChatError> {
        // 设置发送者信息（只设置一次）
        match &mut message {
            ChatMessage::Message(ref mut msg) => {
                msg.sender_peer_id = self.local_peer_id.to_string();
            }
            ChatMessage::Text(ref mut text) => {
                text.sender_peer_id = self.local_peer_id.to_string();
            }
            ChatMessage::TypingIndicator(ref mut indicator) => {
                indicator.sender_peer_id = self.local_peer_id.to_string();
            }
            ChatMessage::Ack(_) => {}
        }

        // 并发发送给所有目标
        let results = futures::future::join_all(
            targets.into_iter().map(|peer_id| self.send(peer_id, message.clone()))
        ).await;

        // 统计失败数量
        let failure_count = results.iter().filter(|r| r.is_err()).count();

        if failure_count > 0 {
            Err(ChatError::PartialFailure(failure_count))
        } else {
            Ok(())
        }
    }

    /// 处理收到的消息
    pub async fn handle_received_message(&self, from: PeerId, message: ChatMessage) {
        // 保存到数据库
        if let Some(db) = self.get_database().await {
            if let (Some(msg_id), Some(content), Some(msg_type)) = (
                message.id().map(|id| id.to_string()),
                message.content().cloned(),
                Some(message.message_type()),
            ) {
                let peer_id_str = from.to_string();
                let sender_id = message.sender_peer_id().unwrap_or("").to_string();

                if let Ok(conversation) = db.get_or_create_conversation(&peer_id_str, None).await {
                    // 序列化消息内容
                    let content_json = serde_json::to_string(&content)
                        .unwrap_or_else(|_| "{}".to_string());

                    // 🔥 序列化 extra 字段单独存储（便于查询）
                    let extra_json = if !content.extra.is_empty() {
                        Some(serde_json::to_string(&content.extra)
                            .unwrap_or_else(|_| "{}".to_string()))
                    } else {
                        None
                    };

                    let mut db_message = DbMessage::new(
                        conversation.id.clone(),
                        sender_id,
                        msg_type,
                        content_json,
                    );

                    // 🔥 设置 extra 字段
                    db_message.extra = extra_json;

                    let _ = db.insert_message(db_message).await;

                    // 更新会话
                    let last_msg_text = extract_text_from_content(&content);
                    let _ = db.update_conversation(
                        &conversation.id,
                        Some(last_msg_text.unwrap_or_else(|| format!("{:?}", msg_type))),
                        Some(msg_type),
                        Some(chrono::Utc::now().timestamp_millis()),
                        true, // 接收的消息增加未读数
                    ).await;
                }
            }
        }

        // 保存到会话历史（内存）
        let mut sessions = self.sessions.write().await;
        let session = sessions
            .entry(from)
            .or_insert_with(|| ChatSession::new(from));

        session.add_to_history(message.clone());

        // 发送事件通知
        let event = match &message {
            ChatMessage::Message(_) | ChatMessage::Text(_) => ChatEvent::MessageReceived {
                from,
                message,
            },
            ChatMessage::TypingIndicator(typing) => ChatEvent::PeerTyping {
                from,
                is_typing: typing.is_typing,
            },
            ChatMessage::Ack(ack) => ChatEvent::MessageAcknowledged {
                from,
                message_id: ack.message_id.clone(),
            },
        };

        let _ = self.event_tx.send(event);
    }

    /// 获取会话的消息历史
    pub async fn get_history(&self, peer_id: &PeerId) -> Vec<ChatMessage> {
        let sessions = self.sessions.read().await;
        sessions
            .get(peer_id)
            .map(|s| s.get_history())
            .unwrap_or_default()
    }

    /// 获取所有可聊天节点（从 NodeManager 复用）
    pub async fn available_peers(&self) -> Vec<crate::VerifiedNode> {
        self.node_manager.list_online_nodes().await
    }

    /// 关闭指定会话
    pub async fn close_session(&self, peer_id: &PeerId) {
        let mut sessions = self.sessions.write().await;
        if let Some(_session) = sessions.remove(peer_id) {
            tracing::info!("关闭与 {} 的聊天会话", peer_id);
            let _ = self.event_tx.send(ChatEvent::SessionClosed {
                peer_id: *peer_id,
            });
        }
    }

    /// 获取待发送的编码消息（用于通过 Swarm 发送）
    ///
    /// 此方法会自动从待发送队列中移除消息
    pub async fn get_pending_message(&self, peer_id: &PeerId) -> Option<Vec<u8>> {
        let mut sessions = self.sessions.write().await;
        if let Some(session) = sessions.get_mut(peer_id) {
            if let Some(msg) = session.dequeue_message() {
                // 编码消息
                if let Ok(encoded) = session.encode_message(msg.clone()) {
                    return Some(encoded);
                }
            }
        }
        None
    }

    /// 获取待发送的 ChatMessage（用于通过 request_response 发送）
    ///
    /// 此方法会自动从待发送队列中移除消息
    pub async fn get_pending_chat_message(&self, peer_id: &PeerId) -> Option<ChatMessage> {
        let mut sessions = self.sessions.write().await;
        if let Some(session) = sessions.get_mut(peer_id) {
            return session.dequeue_message();
        }
        None
    }

    /// 获取待发送消息数量
    pub async fn pending_message_count(&self, peer_id: &PeerId) -> usize {
        let sessions = self.sessions.read().await;
        if let Some(session) = sessions.get(peer_id) {
            session.pending_count()
        } else {
            0
        }
    }

    /// 处理收到的原始数据（来自 Swarm Stream）
    pub async fn handle_raw_data(&self, from: PeerId, data: &[u8]) -> Result<(), ChatError> {
        let mut sessions = self.sessions.write().await;
        let session = sessions
            .entry(from)
            .or_insert_with(|| ChatSession::new(from));

        let message = session.decode_message(data)?;

        // 发送事件通知
        let event = match &message {
            ChatMessage::Message(_) | ChatMessage::Text(_) => ChatEvent::MessageReceived {
                from,
                message,
            },
            ChatMessage::TypingIndicator(typing) => ChatEvent::PeerTyping {
                from,
                is_typing: typing.is_typing,
            },
            ChatMessage::Ack(ack) => ChatEvent::MessageAcknowledged {
                from,
                message_id: ack.message_id.clone(),
            },
        };

        let _ = self.event_tx.send(event);
        Ok(())
    }

    /// 获取事件接收器
    ///
    /// 注意：这会返回一个新的接收器，调用者需要自己管理接收器的生命周期。
    /// 通常在创建 ChatManager 时就应该保存原始的接收器。
    pub fn event_tx(&self) -> mpsc::UnboundedSender<ChatEvent> {
        self.event_tx.clone()
    }

    /// 获取数据库实例（如果已初始化）
    pub async fn get_database(&self) -> Option<Arc<SqliteChatDatabase>> {
        let db_guard = self.database.lock().await;
        db_guard.clone()
    }

    /// 获取所有会话（从数据库）
    pub async fn get_conversations(&self) -> Result<Vec<super::database::models::Conversation>, ChatError> {
        crate::send_log("INFO", "chat_manager", "💬 get_conversations 被调用".to_string());
        if let Some(db) = self.get_database().await {
            let result = db.get_all_conversations().await?;
            crate::send_log("INFO", "chat_manager", format!("💬 数据库返回 {} 个会话", result.len()));
            Ok(result)
        } else {
            crate::send_log("WARN", "chat_manager", "💬 数据库未初始化，返回空列表".to_string());
            Ok(Vec::new())
        }
    }

    /// 获取指定会话的消息（从数据库）
    pub async fn get_conversation_messages(
        &self,
        conversation_id: &str,
        limit: i32,
        before_timestamp: Option<i64>,
    ) -> Result<Vec<super::database::models::Message>, ChatError> {
        crate::send_log("INFO", "chat_manager", format!("💬 get_conversation_messages: conversation_id={}, limit={}",
            conversation_id, limit));
        if let Some(db) = self.get_database().await {
            let result = db.get_messages(conversation_id, limit, before_timestamp).await?;
            crate::send_log("INFO", "chat_manager", format!("💬 数据库返回 {} 条消息", result.len()));
            Ok(result)
        } else {
            crate::send_log("WARN", "chat_manager", "💬 数据库未初始化，返回空列表".to_string());
            Ok(Vec::new())
        }
    }

    /// 通过 peer_id 获取消息（从数据库，支持分页）
    ///
    /// # Arguments
    /// * `peer_id` - 对方的 Peer ID
    /// * `limit` - 每次获取的消息数量
    /// * `before_timestamp` - 获取此时间戳之前的消息（None 表示获取最新消息）
    pub async fn get_messages_by_peer(
        &self,
        peer_id: &str,
        limit: i32,
        before_timestamp: Option<i64>,
    ) -> Result<Vec<super::database::models::Message>, ChatError> {
        crate::send_log("INFO", "chat_manager", format!("💬 get_messages_by_peer: peer_id={}, limit={:?}, before={:?}",
            peer_id, limit, before_timestamp));
        if let Some(db) = self.get_database().await {
            // 先获取或创建会话
            let conversation = db.get_conversation_by_peer(peer_id).await?;
            if let Some(conv) = conversation {
                crate::send_log("INFO", "chat_manager", format!("💬 找到会话: id={}", conv.id));
                let result = db.get_messages(&conv.id, limit, before_timestamp).await?;
                crate::send_log("INFO", "chat_manager", format!("💬 数据库返回 {} 条消息", result.len()));
                Ok(result)
            } else {
                // 会话不存在，返回空列表
                crate::send_log("WARN", "chat_manager", format!("💬 会话不存在: peer_id={}", peer_id));
                Ok(Vec::new())
            }
        } else {
            crate::send_log("WARN", "chat_manager", "💬 数据库未初始化，返回空列表".to_string());
            Ok(Vec::new())
        }
    }
}

/// 从消息内容中提取文本
fn extract_text_from_content(content: &MessageContent) -> Option<String> {
    match content.msg_type {
        MessageType::Text => content.text.clone(),
        MessageType::Image => Some("[图片]".to_string()),
        MessageType::Video => Some("[视频]".to_string()),
        MessageType::File => Some("[文件]".to_string()),
        MessageType::Audio => Some("[语音]".to_string()),
        MessageType::RedPacket => Some("[红包]".to_string()),
        MessageType::System => content.text.clone(),
        MessageType::Unknown | MessageType::Custom => Some("[未知消息]".to_string()),
    }
}

/// 聊天会话
///
/// 管理与单个节点的聊天会话，包括消息历史和连接状态。
pub struct ChatSession {
    /// 对方节点的 Peer ID
    peer_id: PeerId,
    /// 消息历史
    history: VecDeque<ChatMessage>,
    /// 待发送的消息队列
    pending_messages: VecDeque<ChatMessage>,
}

impl ChatSession {
    /// 创建新的聊天会话
    pub fn new(peer_id: PeerId) -> Self {
        Self {
            peer_id,
            history: VecDeque::with_capacity(MAX_HISTORY_SIZE),
            pending_messages: VecDeque::new(),
        }
    }

    /// 发送消息（编码后返回字节数据，供外部通过 Swarm 发送）
    ///
    /// 返回编码后的消息数据，调用者需要通过 Swarm 的 Stream 发送
    pub fn encode_message(&mut self, message: ChatMessage) -> Result<Vec<u8>, ChatError> {
        // 保存到历史
        self.add_to_history(message.clone());

        // 编码消息
        let data = message.encode()?;

        // 添加长度前缀（4 字节，大端序）
        let len = data.len() as u32;
        let mut full_data = Vec::with_capacity(4 + data.len());
        full_data.extend_from_slice(&len.to_be_bytes());
        full_data.extend_from_slice(&data);

        Ok(full_data)
    }

    /// 解码收到的消息数据
    pub fn decode_message(&mut self, data: &[u8]) -> Result<ChatMessage, ChatError> {
        if data.len() < 4 {
            return Err(ChatError::Deserialization("数据太短".to_string()));
        }

        let len = u32::from_be_bytes([data[0], data[1], data[2], data[3]]) as usize;
        if data.len() < 4 + len {
            return Err(ChatError::Deserialization("数据不完整".to_string()));
        }

        let message_data = &data[4..4 + len];
        let message = ChatMessage::decode(message_data)?;

        // 保存到历史
        self.add_to_history(message.clone());

        Ok(message)
    }

    /// 添加待发送消息
    pub fn enqueue_message(&mut self, message: ChatMessage) {
        self.pending_messages.push_back(message);
    }

    /// 获取待发送的消息
    pub fn dequeue_message(&mut self) -> Option<ChatMessage> {
        self.pending_messages.pop_front()
    }

    /// 添加消息到历史
    pub fn add_to_history(&mut self, message: ChatMessage) {
        self.history.push_back(message);

        // 限制历史大小
        while self.history.len() > MAX_HISTORY_SIZE {
            self.history.pop_front();
        }
    }

    /// 获取消息历史
    pub fn get_history(&self) -> Vec<ChatMessage> {
        self.history.iter().cloned().collect()
    }

    /// 获取会话的 Peer ID
    pub fn peer_id(&self) -> PeerId {
        self.peer_id
    }

    /// 检查是否有待发送的消息
    pub fn has_pending_messages(&self) -> bool {
        !self.pending_messages.is_empty()
    }

    /// 获取待发送消息数量
    pub fn pending_count(&self) -> usize {
        self.pending_messages.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::node::NodeManagerConfig;

    #[tokio::test]
    async fn test_chat_manager_creation() {
        let node_manager = Arc::new(NodeManager::new(NodeManagerConfig::default()));
        let local_peer_id = PeerId::random();

        let (manager, mut event_rx) = ChatManager::new(node_manager, local_peer_id);

        // 验证可用节点列表
        let peers = manager.available_peers().await;
        assert!(peers.is_empty());

        // 验证事件通道
        assert!(event_rx.try_recv().is_err());
    }

    #[tokio::test]
    async fn test_chat_session_creation() {
        let peer_id = PeerId::random();
        let session = ChatSession::new(peer_id);

        assert_eq!(session.peer_id(), peer_id);
        assert!(session.get_history().is_empty());
    }

    #[tokio::test]
    async fn test_chat_session_history() {
        let peer_id = PeerId::random();
        let mut session = ChatSession::new(peer_id);

        let msg1 = ChatMessage::text("Hello".to_string());
        let msg2 = ChatMessage::text("World".to_string());

        session.add_to_history(msg1.clone());
        session.add_to_history(msg2.clone());

        let history = session.get_history();
        assert_eq!(history.len(), 2);
        assert_eq!(history[0], msg1);
        assert_eq!(history[1], msg2);
    }

    #[tokio::test]
    async fn test_chat_session_encode_message() {
        let peer_id = PeerId::random();
        let mut session = ChatSession::new(peer_id);

        let msg = ChatMessage::text("Test".to_string());
        let result = session.encode_message(msg.clone());

        assert!(result.is_ok());
        let encoded = result.unwrap();

        // 验证编码包含长度前缀和数据
        assert!(encoded.len() >= 4);

        // 验证消息已添加到历史
        let history = session.get_history();
        assert_eq!(history.len(), 1);
        assert_eq!(history[0], msg);
    }

    #[tokio::test]
    async fn test_chat_session_history_limit() {
        let peer_id = PeerId::random();
        let mut session = ChatSession::new(peer_id);

        // 添加超过 MAX_HISTORY_SIZE 的消息
        for i in 0..(MAX_HISTORY_SIZE + 100) {
            session.add_to_history(ChatMessage::text(format!("Message {}", i)));
        }

        // 验证历史大小被限制
        let history = session.get_history();
        assert_eq!(history.len(), MAX_HISTORY_SIZE);
    }
}
