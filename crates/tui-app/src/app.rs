//! TUI 应用主逻辑
//!
//! 管理应用状态和主事件循环。

use crate::components::{NodeItem, NodeListState, NodeStatus, AppTab, ChatPanelState};
use crate::event::{AppResult, Event};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use futures::StreamExt;
use libp2p::PeerId;
use mdns::{
    ManagedDiscovery, ManagedDiscoveryEvent, NodeManager, NodeManagerConfig,
    HealthCheckConfig, UserInfo, ChatExtension, ChatMessage, ChatEvent,
};
use ratatui::{
    backend::CrosstermBackend,
    Terminal,
};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc;

/// TUI 应用
pub struct TuiApp {
    /// 节点管理器
    node_manager: Arc<NodeManager>,
    /// 节点列表状态
    node_list_state: NodeListState,
    /// 用户信息映射（peer_id -> user_info）
    user_info_map: std::collections::HashMap<PeerId, mdns::UserInfo>,
    /// 设备名称
    device_name: String,
    /// 本地 Peer ID
    local_peer_id: PeerId,
    /// 当前选中的 Tab
    current_tab: AppTab,
    /// 聊天面板状态
    chat_panel_state: ChatPanelState,
    /// 发送消息的命令发送器
    cmd_tx: Option<mpsc::Sender<(Vec<PeerId>, ChatMessage)>>,
    /// 运行状态
    running: bool,
}

impl TuiApp {
    /// 创建新的 TUI 应用
    pub async fn new(device_name: String) -> AppResult<Self> {
        // 创建用户信息
        let user_info = UserInfo::new(device_name.clone())
            .with_status("在线".to_string());

        // 创建节点管理器配置
        let config = NodeManagerConfig::new()
            .with_protocol_version("/localp2p/1.0.0".to_string())
            .with_agent_prefix(Some("localp2p-rust/".to_string()))
            .with_device_name(device_name.clone());

        // 创建节点管理器
        let node_manager = Arc::new(NodeManager::new(config));

        // 启动后台清理任务
        let _cleanup_handle = node_manager.clone().spawn_cleanup_task();

        // 创建健康检查配置
        let health_config = HealthCheckConfig {
            heartbeat_interval: Duration::from_secs(10),
            max_failures: 3,
        };

        // 创建管理式服务发现器
        let listen_addresses = vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()];
        let discovery = ManagedDiscovery::new(
            node_manager.clone(),
            listen_addresses,
            health_config,
            user_info,
        ).await?;

        let local_peer_id = discovery.local_peer_id();

        // 启动发现任务，将事件发送到主事件通道
        // 注意：这需要在 run() 方法中进行，因为我们需要 event_tx

        Ok(Self {
            node_manager,
            node_list_state: NodeListState::default(),
            user_info_map: std::collections::HashMap::new(),
            device_name,
            local_peer_id,
            current_tab: AppTab::Panel1,
            chat_panel_state: ChatPanelState::new(local_peer_id),
            cmd_tx: None,
            running: true,
        })
    }

    /// 运行应用
    pub async fn run(&mut self) -> AppResult<()> {
        use crossterm::event::EventStream;

        // 启用原始模式
        crossterm::terminal::enable_raw_mode()?;

        // 进入备用屏幕
        crossterm::execute!(
            std::io::stdout(),
            crossterm::terminal::EnterAlternateScreen
        )?;

        // 创建终端
        let backend = CrosstermBackend::new(std::io::stdout());
        let mut terminal = Terminal::new(backend)?;

        // 创建事件通道
        let (event_tx, mut event_rx) = mpsc::channel(100);

        // 创建发送消息的命令通道 (PeerId, ChatMessage)
        let (cmd_tx, mut cmd_rx) = mpsc::channel::<(Vec<PeerId>, ChatMessage)>(100);

        // 保存 cmd_tx 到 TuiApp
        self.cmd_tx = Some(cmd_tx.clone());

        // 创建发现器并启动发现任务
        let discovery_tx = event_tx.clone();
        let node_manager = self.node_manager.clone();
        let device_name = self.device_name.clone();

        tokio::spawn(async move {
            // 重新创建发现器（在独立任务中）
            let user_info = UserInfo::new(device_name.clone())
                .with_status("在线".to_string());

            let _config = NodeManagerConfig::new()
                .with_protocol_version("/localp2p/1.0.0".to_string())
                .with_agent_prefix(Some("localp2p-rust/".to_string()))
                .with_device_name(device_name);

            let health_config = HealthCheckConfig {
                heartbeat_interval: Duration::from_secs(10),
                max_failures: 3,
            };

            let listen_addresses = vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()];

            let discovery = ManagedDiscovery::new(
                node_manager,
                listen_addresses,
                health_config,
                user_info,
            ).await;

            if let Err(err) = &discovery {
                tracing::error!("创建发现器失败: {:?}", err);
                return;
            }

            let mut discovery = discovery.unwrap();

            // 启用聊天功能
            if let Err(err) = discovery.enable_chat().await {
                tracing::error!("启用聊天功能失败: {:?}", err);
                return;
            }

            // 获取聊天事件接收器
            let mut chat_event_rx = match discovery.take_chat_events() {
                Some(rx) => rx,
                None => {
                    tracing::error!("无法获取聊天事件接收器");
                    return;
                }
            };

            // 使用 select! 同时监听发现事件、发送命令和聊天事件
            loop {
                tokio::select! {
                    // 处理发现事件
                    event_result = discovery.run() => {
                        match event_result {
                            Ok(event) => {
                                if discovery_tx.send(Event::Discovery(event)).await.is_err() {
                                    break;
                                }
                            }
                            Err(err) => {
                                tracing::error!("发现事件错误: {:?}", err);
                                // 继续运行，不中断
                            }
                        }
                    }
                    // 处理发送消息命令
                    Some((targets, message)) = cmd_rx.recv() => {
                        tracing::info!("发送消息给 {} 个目标", targets.len());
                        if let Err(err) = discovery.broadcast_message(targets, message).await {
                            tracing::error!("发送消息失败: {:?}", err);
                        }
                    }
                    // 处理聊天事件
                    Some(chat_event) = chat_event_rx.recv() => {
                        tracing::debug!("转发聊天事件: {:?}", chat_event);
                        if discovery_tx.send(Event::Chat(chat_event)).await.is_err() {
                            break;
                        }
                    }
                }
            }
        });

        // 启动键盘监听
        let event_tx_clone = event_tx.clone();
        tokio::spawn(async move {
            let mut reader = EventStream::new();
            while let Some(event) = reader.next().await {
                match event {
                    Ok(crossterm::event::Event::Key(key_event)) => {
                        if key_event.kind == crossterm::event::KeyEventKind::Press {
                            let _ = event_tx_clone.send(Event::Input(key_event)).await;
                        }
                    }
                    Ok(_) => {}
                    Err(err) => {
                        tracing::error!("键盘事件错误: {:?}", err);
                        break;
                    }
                }
            }
        });

        // 启动定时器
        let event_tx_clone = event_tx.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_millis(250));
            loop {
                interval.tick().await;
                if event_tx_clone.send(Event::Tick).await.is_err() {
                    break;
                }
            }
        });

        // 主事件循环
        while self.running {
            // 绘制 UI
            terminal.draw(|f| {
                crate::ui::draw_ui(f, self);
            })?;

            // 处理事件
            match event_rx.recv().await {
                Some(Event::Input(key_event)) => {
                    self.handle_key_event(key_event)?;
                }
                Some(Event::Paste(content)) => {
                    self.handle_paste_event(content)?;
                }
                Some(Event::Discovery(discovery_event)) => {
                    self.handle_discovery_event(discovery_event).await;
                }
                Some(Event::Chat(chat_event)) => {
                    self.handle_chat_event(chat_event).await;
                }
                Some(Event::Tick) => {
                    self.update();
                }
                None => {
                    break;
                }
            }
        }

        // 清理
        crossterm::terminal::disable_raw_mode()?;
        crossterm::execute!(
            terminal.backend_mut(),
            crossterm::terminal::LeaveAlternateScreen
        )?;

        Ok(())
    }

    /// 处理键盘事件
    fn handle_key_event(&mut self, key_event: KeyEvent) -> AppResult<()> {
        match key_event.code {
            KeyCode::Char('q') | KeyCode::Char('c') if key_event.modifiers.contains(KeyModifiers::CONTROL) => {
                self.running = false;
            }
            // Tab 切换焦点
            KeyCode::Tab => {
                self.current_tab = self.current_tab.next();
                // 如果从面板1切换到面板2，设置选中的节点为聊天对象
                if self.current_tab == AppTab::Panel2 {
                    let selected_peers = self.node_list_state.get_selected_peer_ids();
                    if !selected_peers.is_empty() {
                        self.chat_panel_state.set_active_chats(selected_peers);
                    }
                }
            }
            // 方向键操作（仅在焦点在面板1时有效）
            KeyCode::Up if self.current_tab == AppTab::Panel1 => {
                self.node_list_state.move_up();
            }
            KeyCode::Down if self.current_tab == AppTab::Panel1 => {
                self.node_list_state.move_down();
            }
            KeyCode::Enter if self.current_tab == AppTab::Panel1 => {
                self.node_list_state.set_single_selection();
            }
            KeyCode::Char(' ') if self.current_tab == AppTab::Panel1 => {
                self.node_list_state.toggle_selection();
            }
            // 聊天面板输入处理（当焦点在面板2时）
            KeyCode::Enter if self.current_tab == AppTab::Panel2 => {
                // 发送消息
                let input = self.chat_panel_state.take_input();
                if !input.is_empty() {
                    let message = ChatMessage::text(input.clone());
                    let targets = self.chat_panel_state.active_chats().to_vec();

                    if !targets.is_empty() {
                        // 先添加到聊天历史（用于立即显示），使用本地 Peer ID
                        self.chat_panel_state.add_message(self.local_peer_id, message.clone());

                        // 通过 cmd_tx 发送消息到 discovery 任务
                        if let Some(ref cmd_tx) = self.cmd_tx {
                            if let Err(err) = cmd_tx.try_send((targets, message)) {
                                tracing::error!("发送消息失败: {:?}", err);
                            }
                        }
                    } else {
                        tracing::warn!("没有选择聊天对象");
                    }
                }
            }
            KeyCode::Backspace if self.current_tab == AppTab::Panel2 => {
                self.chat_panel_state.handle_backspace();
            }
            KeyCode::Left if self.current_tab == AppTab::Panel2 => {
                self.chat_panel_state.move_cursor_left();
            }
            KeyCode::Right if self.current_tab == AppTab::Panel2 => {
                self.chat_panel_state.move_cursor_right();
            }
            KeyCode::Up if self.current_tab == AppTab::Panel2 => {
                self.chat_panel_state.scroll_up();
            }
            KeyCode::Down if self.current_tab == AppTab::Panel2 => {
                self.chat_panel_state.scroll_down();
            }
            // 字符输入：在面板2时允许所有字符（包括 q），在面板1时按 q 退出
            KeyCode::Char(c) if self.current_tab == AppTab::Panel2 => {
                self.chat_panel_state.handle_input_char(c);
            }
            KeyCode::Char('q') => {
                // 只在非聊天面板时，q 键退出
                self.running = false;
            }
            _ => {}
        }
        Ok(())
    }

    /// 处理粘贴/输入法输入事件
    fn handle_paste_event(&mut self, content: String) -> AppResult<()> {
        // 只在聊天面板且当前是面板2时处理
        if self.current_tab == AppTab::Panel2 {
            // 将每个字符添加到输入缓冲区
            for c in content.chars() {
                self.chat_panel_state.handle_input_char(c);
            }
        }
        Ok(())
    }

    /// 处理发现事件
    async fn handle_discovery_event(&mut self, event: ManagedDiscoveryEvent) {
        match event {
            ManagedDiscoveryEvent::Discovered(peer_id, _addr) => {
                tracing::info!("发现节点: {}", peer_id);
            }
            ManagedDiscoveryEvent::Expired(peer_id) => {
                tracing::debug!("节点 mDNS 记录过期: {}", peer_id);
            }
            ManagedDiscoveryEvent::Verified(peer_id) => {
                tracing::info!("节点验证通过: {}", peer_id);
                // 获取节点信息
                if let Some(node) = self.node_manager.get_node(&peer_id).await {
                    let node_item = NodeItem {
                        peer_id: node.peer_id,
                        display_name: node.display_name(),
                        device_name: node.name.clone().unwrap_or_default(),
                        status: NodeStatus::Online,
                        addresses: node.addresses.iter().map(|a| a.to_string()).collect(),
                    };
                    self.node_list_state.add_node(node_item);
                }
            }
            ManagedDiscoveryEvent::VerificationFailed(peer_id, reason) => {
                tracing::warn!("节点验证失败: {} - {}", peer_id, reason);
            }
            ManagedDiscoveryEvent::UserInfoReceived(peer_id, user_info) => {
                tracing::info!("收到用户信息: {} - {}", peer_id, user_info.display_name());
                // 保存用户信息
                self.user_info_map.insert(peer_id, user_info.clone());

                // 更新节点的显示名称
                let display_name = user_info.display_name();
                let device_name = user_info.device_name.clone();
                self.node_list_state.update_node(&peer_id, |node| {
                    node.display_name = display_name.clone();
                    node.device_name = device_name.clone();
                });
            }
            ManagedDiscoveryEvent::NodeRecovered(peer_id, _rtt) => {
                tracing::info!("节点恢复健康: {}", peer_id);
                self.node_list_state.update_node(&peer_id, |node| {
                    node.status = NodeStatus::Online;
                });
            }
            ManagedDiscoveryEvent::NodeOffline(peer_id) => {
                tracing::info!("节点离线: {}", peer_id);
                self.node_list_state.remove_node(&peer_id);
                self.user_info_map.remove(&peer_id);
            }
        }
    }

    /// 处理聊天事件
    async fn handle_chat_event(&mut self, event: ChatEvent) {
        match event {
            ChatEvent::MessageReceived { from, message } => {
                tracing::info!("收到来自 {} 的消息", from);
                self.chat_panel_state.add_message(from, message);
            }
            ChatEvent::MessageSent { to, message_id } => {
                tracing::info!("消息 {} 已发送给 {}", message_id, to);
            }
            ChatEvent::PeerTyping { from, is_typing } => {
                self.chat_panel_state.set_peer_typing(from, is_typing);
            }
            _ => {
                tracing::debug!("未处理的聊天事件: {:?}", event);
            }
        }
    }

    /// 更新应用状态
    fn update(&mut self) {
        // 定期更新逻辑
        // 可以在这里处理一些定时的状态更新
    }

    /// 获取设备名称
    pub fn device_name(&self) -> &str {
        &self.device_name
    }

    /// 获取节点列表状态
    pub fn node_list_state(&self) -> &NodeListState {
        &self.node_list_state
    }

    /// 获取本地 Peer ID
    pub fn local_peer_id(&self) -> PeerId {
        self.local_peer_id
    }

    /// 获取当前选中的 Tab
    pub fn current_tab(&self) -> AppTab {
        self.current_tab
    }

    /// 获取选中节点的详情
    pub fn selected_node_details(&self) -> Option<String> {
        if let Some(node) = self.node_list_state.get_current() {
            // 尝试获取用户信息
            let user_info = self.user_info_map.get(&node.peer_id);

            let mut details = format!(
                "Peer ID: {}\n设备名: {}\n状态: {}",
                node.peer_id,
                node.device_name,
                node.status.as_str()
            );

            if let Some(info) = user_info {
                details.push_str(&format!("\n昵称: {}", info.display_name()));
                if let Some(ref status) = info.status {
                    details.push_str(&format!("\n状态: {}", status));
                }
            }

            if let Some(addr) = node.addresses.first() {
                details.push_str(&format!("\n地址: {}", addr));
            }

            Some(details)
        } else {
            None
        }
    }

    /// 获取用户信息
    pub fn get_user_info(&self, peer_id: &PeerId) -> Option<&mdns::UserInfo> {
        self.user_info_map.get(peer_id)
    }

    /// 获取聊天面板状态
    pub fn chat_panel_state(&self) -> &ChatPanelState {
        &self.chat_panel_state
    }
}

/// 运行 TUI 应用的便捷函数
pub async fn run_tui(device_name: String) -> AppResult<()> {
    let mut app = TuiApp::new(device_name).await?;
    app.run().await
}
