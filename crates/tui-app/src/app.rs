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
    P2PManager, P2PManagerConfig,
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
    local_peer_id: Option<PeerId>,
    /// 临时密钥对（每次运行随机生成，不保存到文件）
    identity: Option<libp2p::identity::Keypair>,
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
    /// 创建新的 TUI 应用（使用临时密钥，每个实例有不同的 Peer ID）
    pub async fn new(device_name: String) -> AppResult<Self> {
        // 创建节点管理器配置
        let config = NodeManagerConfig::new()
            .with_protocol_version("/localp2p/1.0.0".to_string())
            .with_agent_prefix(Some("localp2p-rust/".to_string()))
            .with_device_name(device_name.clone());

        // 创建节点管理器
        let node_manager = Arc::new(NodeManager::new(config));

        // 启动后台清理任务
        let _cleanup_handle = node_manager.clone().spawn_cleanup_task();

        // ⚠️ TUI 使用临时密钥，不保存到文件
        // 这样同一台设备的多个 TUI 实例会有不同的 Peer ID，便于测试
        let identity = libp2p::identity::Keypair::generate_ed25519();
        let peer_id = identity.public().to_peer_id();

        tracing::info!("TUI 使用临时密钥（不保存到文件），Peer ID: {}", peer_id);
        tracing::info!("💡 提示：每次运行都会生成新的 Peer ID");

        Ok(Self {
            node_manager,
            node_list_state: NodeListState::default(),
            user_info_map: std::collections::HashMap::new(),
            device_name,
            local_peer_id: Some(peer_id),
            identity: Some(identity),
            current_tab: AppTab::Panel1,
            chat_panel_state: ChatPanelState::new(peer_id),
            cmd_tx: None,
            running: true,
        })
    }

    /// 运行应用
    pub async fn run(&mut self) -> AppResult<()> {
        use crossterm::event::EventStream;

        // ⚠️ TUI 使用在 new() 中生成的临时密钥
        // 不再从文件加载密钥对

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

        // ⚠️ 使用主线程中生成的临时密钥
        let identity = self.identity.clone().unwrap_or_else(|| {
            tracing::error!("密钥未初始化，生成新的临时密钥");
            libp2p::identity::Keypair::generate_ed25519()
        });

        tracing::info!("后台任务使用临时密钥对，Peer ID: {}", identity.public().to_peer_id());

        tokio::spawn(async move {
            // 创建用户信息
            let user_info = UserInfo::new(device_name.clone())
                .with_status("在线".to_string());

            let health_config = HealthCheckConfig {
                heartbeat_interval: Duration::from_secs(10),
                max_failures: 3,
            };

            let listen_addresses = vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()];

            // 使用临时密钥对创建发现器
            let discovery = ManagedDiscovery::new(
                node_manager,
                listen_addresses,
                health_config,
                user_info,
                Some(identity),  // 传入临时密钥对
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
                        self.chat_panel_state.add_message(self.local_peer_id(), message.clone());

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
            ManagedDiscoveryEvent::Discovered(peer_id, addr) => {
                let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f");
                tracing::info!("╔═══════════════════════════════════════════════════════════════");
                tracing::info!("║ 🔍 [TUI] mDNS 发现事件 - {}", timestamp);
                tracing::info!("║ 发现设备: {}", peer_id);
                tracing::info!("║ 地址: {}", addr);
                tracing::info!("╠═══════════════════════════════════════════════════════════════");

                // 解析地址信息
                let addr_str = addr.to_string();
                if let Some(ip_start) = addr_str.find("ip4/") {
                    if let Some(ip_end) = addr_str[ip_start..].find("/tcp/") {
                        let ip = &addr_str[ip_start + 4..ip_start + ip_end];
                        tracing::info!("║ IP 地址: {}", ip);

                        let port_start = ip_start + ip_end + 5;
                        if let Some(port_end) = addr_str[port_start..].find('/') {
                            let port = &addr_str[port_start..port_start + port_end];
                            tracing::info!("║ 端口: {}", port);
                        }
                    }
                }

                tracing::info!("╚═══════════════════════════════════════════════════════════════");
            }
            ManagedDiscoveryEvent::Expired(peer_id) => {
                let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f");
                tracing::info!("╔═══════════════════════════════════════════════════════════════");
                tracing::info!("║ ⏰ [TUI] mDNS 过期事件 - {}", timestamp);
                tracing::info!("║ 设备离线: {}", peer_id);
                tracing::info!("╚═══════════════════════════════════════════════════════════════");
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
        self.local_peer_id.unwrap_or_else(|| {
            tracing::warn!("local_peer_id 尚未初始化，使用临时值");
            PeerId::random()
        })
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

/// 运行 TUI 应用的便捷函数（旧架构：ManagedDiscovery）
pub async fn run_tui(device_name: String) -> AppResult<()> {
    let mut app = TuiApp::new(device_name).await?;
    app.run().await
}

// ============================================================================
// 新架构：使用 P2PManager（服务分离）
// ============================================================================

/// TUI 应用（新架构：P2PManager 服务分离）
pub struct TuiAppNew {
    /// P2P 管理器
    p2p_manager: Arc<tokio::sync::Mutex<P2PManager>>,
    /// 节点管理器
    node_manager: Arc<NodeManager>,
    /// 节点列表状态
    node_list_state: NodeListState,
    /// 设备名称
    device_name: String,
    /// 本地 Peer ID
    local_peer_id: PeerId,
    /// 当前选中的 Tab
    current_tab: AppTab,
    /// 聊天面板状态
    chat_panel_state: ChatPanelState,
    /// 发送消息的命令发送器
    cmd_tx: Option<mpsc::Sender<(Vec<PeerId>, String)>>,
    /// 运行状态
    running: bool,
}

impl TuiAppNew {
    /// 创建新的 TUI 应用（使用新架构：P2PManager）
    pub async fn new(device_name: String) -> AppResult<Self> {
        tracing::info!("╔═══════════════════════════════════════════════════════════════════════════════");
        tracing::info!("║ 🚀 [TUI 新架构] 开始初始化...");
        tracing::info!("╚═══════════════════════════════════════════════════════════════════════════════");

        // 创建临时密钥对
        tracing::info!("📝 [步骤 1/7] 生成临时密钥对...");
        let identity = libp2p::identity::Keypair::generate_ed25519();
        let peer_id = identity.public().to_peer_id();

        tracing::info!("✓ [步骤 1/7] 密钥对生成成功");
        tracing::info!("  └─ Peer ID: {}", peer_id);
        tracing::info!("  └─ 密钥类型: Ed25519");
        tracing::info!("  └─ 持久化: 否（每次运行生成新密钥）");

        // 创建用户信息
        tracing::info!("📝 [步骤 2/7] 创建用户信息...");
        let user_info = UserInfo::new(device_name.clone())
            .with_status("在线".to_string());

        tracing::info!("✓ [步骤 2/7] 用户信息创建成功");
        tracing::info!("  └─ 设备名称: {}", device_name);
        tracing::info!("  └─ 状态: {}", user_info.status.as_ref().unwrap_or(&"未设置".to_string()));

        // 创建节点管理器配置
        tracing::info!("📝 [步骤 3/7] 创建节点管理器配置...");
        let node_manager_config = NodeManagerConfig::new()
            .with_protocol_version("/localp2p/1.0.0".to_string())
            .with_agent_prefix(Some("localp2p-rust/".to_string()))
            .with_device_name(device_name.clone());

        tracing::info!("✓ [步骤 3/7] 节点管理器配置创建成功");
        tracing::info!("  └─ 协议版本: /localp2p/1.0.0");
        tracing::info!("  └─ 代理前缀: localp2p-rust/");

        // 创建节点管理器
        tracing::info!("📝 [步骤 4/7] 创建节点管理器...");
        let node_manager = Arc::new(NodeManager::new(node_manager_config.clone()));

        tracing::info!("✓ [步骤 4/7] 节点管理器创建成功");
        tracing::info!("  └─ NodeManager 地址: {:p}", node_manager);

        // 启动后台清理任务
        tracing::info!("📝 [步骤 5/7] 启动后台清理任务...");
        node_manager.clone().spawn_cleanup_task();
        tracing::info!("✓ [步骤 5/7] 后台清理任务已启动");
        tracing::info!("  └─ 清理间隔: 60 秒");
        tracing::info!("  └─ 节点超时: 300 秒");

        // 创建健康检查配置
        tracing::info!("📝 [步骤 6/7] 创建健康检查配置...");
        let health_config = HealthCheckConfig {
            heartbeat_interval: Duration::from_secs(10),
            max_failures: 3,
        };

        tracing::info!("✓ [步骤 6/7] 健康检查配置创建成功");
        tracing::info!("  └─ 心跳间隔: 10 秒");
        tracing::info!("  └─ 最大失败次数: 3 次");

        // 创建 P2PManager 配置
        tracing::info!("📝 [步骤 7/7] 创建 P2PManager 配置...");
        let p2p_config = P2PManagerConfig::new()
            .with_identity(identity.clone())
            .with_node_manager_config(node_manager_config)
            .with_node_manager(node_manager.clone())
            .with_local_user_info(user_info)
            .with_health_check_config(health_config)
            .with_listen_addresses(vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()]);

        tracing::info!("✓ [步骤 7/7] P2PManager 配置创建成功");
        tracing::info!("  └─ 监听地址: /ip4/0.0.0.0/tcp/0 (自动分配端口)");
        tracing::info!("  └─ NodeManager: 已共享");

        // 创建 P2PManager
        tracing::info!("📝 [P2PManager] 正在创建 P2PManager...");
        let p2p_manager = Arc::new(tokio::sync::Mutex::new(
            P2PManager::new(p2p_config).await
                .map_err(|e| {
                    tracing::error!("❌ [P2PManager] 创建失败: {:?}", e);
                    crate::event::AppError::Mdns(format!("创建 P2PManager 失败: {:?}", e))
                })?
        ));

        tracing::info!("✓ [P2PManager] 创建成功");
        tracing::info!("  └─ P2PManager 地址: {:p}", p2p_manager);

        tracing::info!("╔═══════════════════════════════════════════════════════════════════════════════");
        tracing::info!("║ ✅ [TUI 新架构] 初始化完成");
        tracing::info!("╚═══════════════════════════════════════════════════════════════════════════════");

        Ok(Self {
            p2p_manager,
            node_manager,
            node_list_state: NodeListState::default(),
            device_name,
            local_peer_id: peer_id,
            current_tab: AppTab::Panel1,
            chat_panel_state: ChatPanelState::new(peer_id),
            cmd_tx: None,
            running: true,
        })
    }

    /// 运行应用
    pub async fn run(&mut self) -> AppResult<()> {
        use crossterm::event::EventStream;

        tracing::info!("╔═══════════════════════════════════════════════════════════════════════════════");
        tracing::info!("║ 🚀 [TUI 新架构] 启动运行时...");
        tracing::info!("╚═══════════════════════════════════════════════════════════════════════════════");

        // 启用原始模式
        tracing::debug!("📝 [终端] 启用原始模式...");
        crossterm::terminal::enable_raw_mode()?;
        tracing::debug!("✓ [终端] 原始模式已启用");

        // 进入备用屏幕
        tracing::debug!("📝 [终端] 进入备用屏幕...");
        crossterm::execute!(
            std::io::stdout(),
            crossterm::terminal::EnterAlternateScreen
        )?;
        tracing::debug!("✓ [终端] 备用屏幕已进入");

        // 创建终端
        tracing::debug!("📝 [终端] 创建终端实例...");
        let backend = CrosstermBackend::new(std::io::stdout());
        let mut terminal = Terminal::new(backend)?;
        tracing::debug!("✓ [终端] 终端实例已创建");

        // 创建事件通道
        tracing::debug!("📝 [事件] 创建事件通道...");
        let (event_tx, mut event_rx) = mpsc::channel(100);
        tracing::debug!("✓ [事件] 事件通道已创建 (buffer=100)");

        // 创建发送消息的命令通道 (Vec<PeerId>, String)
        let (cmd_tx, mut cmd_rx) = mpsc::channel::<(Vec<PeerId>, String)>(100);
        self.cmd_tx = Some(cmd_tx.clone());
        tracing::debug!("✓ [命令] 命令通道已创建 (buffer=100)");

        // 启动所有服务
        tracing::info!("╔═══════════════════════════════════════════════════════════════════════════════");
        tracing::info!("║ 📡 [服务启动] 正在启动 P2P 服务...");
        tracing::info!("╚═══════════════════════════════════════════════════════════════════════════════");
        {
            let mut p2p_manager = self.p2p_manager.lock().await;
            tracing::debug!("📝 [服务] 获取 P2PManager 锁...");
            p2p_manager.start_all().await
                .map_err(|e| {
                    tracing::error!("❌ [服务启动] 失败: {:?}", e);
                    crate::event::AppError::Mdns(format!("启动服务失败: {:?}", e))
                })?;
        }
        tracing::info!("✓ [服务启动] P2P 服务启动成功");
        tracing::info!("  └─ mDNS 服务: 运行中");
        tracing::info!("  └─ 连接服务: 运行中");
        tracing::info!("  └─ 健康检查: 已启用");

        // 设置聊天事件回调（收到消息时通过事件通道通知 UI）
        tracing::debug!("📝 [聊天] 设置聊天事件回调...");
        let event_tx_for_chat = event_tx.clone();
        unsafe {
            mdns::set_chat_event_callback(move |from, content| {
                tracing::info!("💬 [聊天回调] 收到来自 {} 的消息: {}", from, content);
                let peer_id = from.parse().unwrap_or_else(|_| libp2p::PeerId::random());
                let message = ChatMessage::text(content);
                // 将消息转换为 ChatEvent 并发送到事件通道（非阻塞）
                if let Err(e) = event_tx_for_chat.try_send(Event::Chat(ChatEvent::MessageReceived {
                    from: peer_id,
                    message,
                })) {
                    tracing::error!("❌ [聊天回调] 发送事件失败（通道可能已满）: {:?}", e);
                }
            });
        }
        tracing::debug!("✓ [聊天] 聊天事件回调已设置");

        // 启动键盘监听
        tracing::debug!("📝 [键盘] 启动键盘监听任务...");
        let event_tx_clone = event_tx.clone();
        tokio::spawn(async move {
            let mut reader = EventStream::new();
            tracing::debug!("✓ [键盘] 键盘监听任务已启动");
            while let Some(event) = reader.next().await {
                match event {
                    Ok(crossterm::event::Event::Key(key_event)) => {
                        if key_event.kind == crossterm::event::KeyEventKind::Press {
                            let _ = event_tx_clone.send(Event::Input(key_event)).await;
                        }
                    }
                    Ok(_) => {}
                    Err(err) => {
                        tracing::error!("❌ [键盘] 键盘事件错误: {:?}", err);
                        break;
                    }
                }
            }
        });

        // 启动节点状态监控（轮询 NodeManager）
        tracing::info!("📝 [监控] 启动节点状态监控任务...");
        let node_manager = self.node_manager.clone();
        let _discovery_tx = event_tx.clone();
        let mut known_nodes: std::collections::HashSet<PeerId> = std::collections::HashSet::new();
        let mut last_log_time = std::time::Instant::now();

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_millis(500));
            tracing::info!("✓ [监控] 节点状态监控任务已启动");
            tracing::info!("  └─ 轮询间隔: 500ms");
            tracing::info!("  └─ 每隔 5 秒输出一次状态摘要");

            loop {
                interval.tick().await;

                let current_nodes = node_manager.list_all_nodes().await;
                let node_count = current_nodes.len();
                let online_count = current_nodes.iter().filter(|n| n.status.is_online()).count();

                // 检测新节点
                let mut new_nodes = Vec::new();
                for node in &current_nodes {
                    if !known_nodes.contains(&node.peer_id) {
                        known_nodes.insert(node.peer_id);
                        let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f");
                        tracing::info!("╔═══════════════════════════════════════════════════════════════════════════════");
                        tracing::info!("║ 🔍 [TUI 新架构] 节点发现事件 - {}", timestamp);
                        tracing::info!("║ Peer ID: {}", node.peer_id);
                        tracing::info!("║ 显示名称: {}", node.display_name());
                        if let Some(ref name) = node.name {
                            tracing::info!("║ 设备名称: {}", name);
                        }
                        if !node.addresses.is_empty() {
                            tracing::info!("║ 地址列表:");
                            for addr in &node.addresses {
                                tracing::info!("║   - {}", addr);
                            }
                        }
                        tracing::info!("║ 状态: {:?}", node.status);
                        tracing::info!("╚═══════════════════════════════════════════════════════════════════════════════");
                        new_nodes.push(node.peer_id);
                    }
                }

                // 检测离线节点
                let current_peer_ids: std::collections::HashSet<PeerId> =
                    current_nodes.iter().map(|n| n.peer_id).collect();
                let offline: Vec<_> = known_nodes.difference(&current_peer_ids).cloned().collect();
                for peer_id in offline {
                    known_nodes.remove(&peer_id);
                    let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f");
                    tracing::info!("╔═══════════════════════════════════════════════════════════════════════════════");
                    tracing::info!("║ ⏰ [TUI 新架构] 节点离线事件 - {}", timestamp);
                    tracing::info!("║ Peer ID: {}", peer_id);
                    tracing::info!("╚═══════════════════════════════════════════════════════════════════════════════");
                }

                // 定期输出状态摘要（每5秒）
                if last_log_time.elapsed() >= Duration::from_secs(5) {
                    last_log_time = std::time::Instant::now();
                    if node_count > 0 {
                        tracing::info!("📊 [TUI 新架构] 节点状态摘要:");
                        tracing::info!("  └─ 总节点数: {}", node_count);
                        tracing::info!("  └─ 在线节点: {}", online_count);
                        tracing::info!("  └─ 离线节点: {}", node_count - online_count);
                        for node in &current_nodes {
                            let status_indicator = if node.status.is_online() { "🟢" } else { "🔴" };
                            tracing::info!("  {} {} - {}", status_indicator, node.peer_id, node.display_name());
                        }
                    } else {
                        tracing::warn!("⚠️  [TUI 新架构] 当前没有发现任何节点");
                        tracing::warn!("  └─ 请检查:");
                        tracing::warn!("    1. 是否在同一局域网内运行了其他 P2P 节点");
                        tracing::warn!("    2. 防火墙是否允许 mDNS (UDP 5353) 和 TCP 通信");
                        tracing::warn!("    3. 网络连接是否正常");
                    }
                }
            }
        });

        // 启动命令处理任务（处理消息发送）
        // 使用 spawn_blocking 避免跨线程传递非 Send 类型
        tracing::debug!("📝 [命令] 启动命令处理任务...");
        let p2p_manager_for_cmd = self.p2p_manager.clone();
        tokio::task::spawn_blocking(move || {
            let rt = tokio::runtime::Handle::try_current()
                .expect("No runtime found");

            tracing::debug!("✓ [命令] 命令处理任务已启动");
            loop {
                // 使用 blocking_recv() 在 spawn_blocking 中接收消息
                match cmd_rx.blocking_recv() {
                    Some((targets, message)) => {
                        for target_peer_id in targets {
                            let target = target_peer_id.to_string();
                            if let Err(e) = rt.block_on(async {
                                p2p_manager_for_cmd.lock().await.send_message(target, message.clone()).await
                            }) {
                                tracing::error!("❌ [命令] 发送消息失败: {}", e);
                            } else {
                                tracing::info!("✓ [命令] 消息已发送给 {}", target_peer_id);
                            }
                        }
                    }
                    None => {
                        tracing::debug!("📡 [命令] 命令通道已关闭");
                        break;
                    }
                }
            }
        });

        // 启动定时器
        tracing::debug!("📝 [定时器] 启动 UI 刷新定时器...");
        let event_tx_clone = event_tx.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_millis(250));
            tracing::debug!("✓ [定时器] UI 刷新定时器已启动 (250ms)");
            loop {
                interval.tick().await;
                if event_tx_clone.send(Event::Tick).await.is_err() {
                    break;
                }
            }
        });

        tracing::info!("╔═══════════════════════════════════════════════════════════════════════════════");
        tracing::info!("║ ✅ [TUI 新架构] 运行时初始化完成，进入主事件循环");
        tracing::info!("╚═══════════════════════════════════════════════════════════════════════════════");

        let mut tick_count = 0u64;
        // 主事件循环
        while self.running {
            // 定期更新节点列表
            let nodes = self.node_manager.list_all_nodes().await;

            // 每20次tick（约5秒）输出一次循环日志
            if tick_count % 20 == 0 {
                tracing::debug!("🔄 [主循环] Tick #{}, 当前节点数: {}", tick_count, nodes.len());
            }
            tick_count += 1;

            for node in &nodes {
                let node_item = NodeItem {
                    peer_id: node.peer_id,
                    display_name: node.display_name(),
                    device_name: node.name.clone().unwrap_or_default(),
                    status: if node.status.is_online() { NodeStatus::Online } else { NodeStatus::Offline },
                    addresses: node.addresses.iter().map(|a| a.to_string()).collect(),
                };
                self.node_list_state.add_node(node_item);
            }

            // 绘制 UI
            terminal.draw(|f| {
                crate::ui::draw_ui_new(f, self);
            })?;

            // 处理事件
            match event_rx.recv().await {
                Some(Event::Input(key_event)) => {
                    self.handle_key_event(key_event)?;
                }
                Some(Event::Chat(chat_event)) => {
                    self.handle_chat_event(chat_event);
                }
                Some(Event::Tick) => {
                    self.update();
                }
                None => {
                    tracing::info!("📡 [主循环] 事件通道已关闭，退出循环");
                    break;
                }
                _ => {}
            }
        }

        tracing::info!("╔═══════════════════════════════════════════════════════════════════════════════");
        tracing::info!("║ 🛑 [TUI 新架构] 正在清理资源...");
        tracing::info!("╚═══════════════════════════════════════════════════════════════════════════════");

        // 清理
        crossterm::terminal::disable_raw_mode()?;
        crossterm::execute!(
            terminal.backend_mut(),
            crossterm::terminal::LeaveAlternateScreen
        )?;

        tracing::info!("✅ [TUI 新架构] 资源清理完成，退出");

        Ok(())
    }

    /// 处理键盘事件
    fn handle_key_event(&mut self, key_event: KeyEvent) -> AppResult<()> {
        match key_event.code {
            KeyCode::Char('q') | KeyCode::Char('c') if key_event.modifiers.contains(KeyModifiers::CONTROL) => {
                self.running = false;
            }
            KeyCode::Tab => {
                self.current_tab = self.current_tab.next();
                if self.current_tab == AppTab::Panel2 {
                    let selected_peers = self.node_list_state.get_selected_peer_ids();
                    if !selected_peers.is_empty() {
                        self.chat_panel_state.set_active_chats(selected_peers);
                    }
                }
            }
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
            KeyCode::Enter if self.current_tab == AppTab::Panel2 => {
                let input = self.chat_panel_state.take_input();
                if !input.is_empty() {
                    let targets = self.chat_panel_state.active_chats().to_vec();
                    if !targets.is_empty() {
                        let message = ChatMessage::text(input.clone());
                        self.chat_panel_state.add_message(self.local_peer_id, message.clone());

                        // ✅ 新架构支持消息发送（使用命令通道）
                        if let Some(ref cmd_tx) = self.cmd_tx {
                            if let Err(err) = cmd_tx.try_send((targets, input)) {
                                tracing::error!("发送消息失败: {:?}", err);
                            }
                        }
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
            KeyCode::Char(c) if self.current_tab == AppTab::Panel2 => {
                self.chat_panel_state.handle_input_char(c);
            }
            KeyCode::Char('q') => {
                self.running = false;
            }
            _ => {}
        }
        Ok(())
    }

    /// 处理聊天事件
    fn handle_chat_event(&mut self, event: ChatEvent) {
        match event {
            ChatEvent::MessageReceived { from, message } => {
                tracing::info!("💬 [TUI] 收到来自 {} 的消息", from);
                self.chat_panel_state.add_message(from, message);
            }
            ChatEvent::MessageSent { to, message_id } => {
                tracing::info!("✓ [TUI] 消息 {} 已发送给 {}", message_id, to);
            }
            ChatEvent::PeerTyping { from, is_typing } => {
                tracing::debug!("⌨️  [TUI] {} {} 输入中", from, if is_typing { "正在" } else { "停止" });
                self.chat_panel_state.set_peer_typing(from, is_typing);
            }
            _ => {
                tracing::debug!("📨 [TUI] 未处理的聊天事件: {:?}", event);
            }
        }
    }

    /// 更新应用状态
    fn update(&mut self) {
        // 定期更新逻辑
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
            let mut details = format!(
                "Peer ID: {}\n设备名: {}\n状态: {} (新架构)",
                node.peer_id,
                node.device_name,
                node.status.as_str()
            );

            if let Some(addr) = node.addresses.first() {
                details.push_str(&format!("\n地址: {}", addr));
            }

            Some(details)
        } else {
            None
        }
    }

    /// 获取用户信息（从节点 attributes 中读取）
    pub fn get_user_info(&self, _peer_id: &PeerId) -> Option<&str> {
        // 新架构中，用户信息存储在节点 attributes 中
        // 这里简化处理，直接返回 None
        None
    }

    /// 获取聊天面板状态
    pub fn chat_panel_state(&self) -> &ChatPanelState {
        &self.chat_panel_state
    }
}

/// 运行 TUI 应用的便捷函数（新架构：P2PManager）
pub async fn run_tui_new(device_name: String) -> AppResult<()> {
    let mut app = TuiAppNew::new(device_name).await?;
    app.run().await
}
