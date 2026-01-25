//! 聊天面板组件
//!
//! 提供功能完整的聊天界面，包括消息列表和输入框。

use libp2p::PeerId;
use mdns::ChatMessage;
use ratatui::{
    buffer::Buffer,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget, Wrap},
};

/// 最大显示的消息条数
const MAX_DISPLAY_MESSAGES: usize = 100;

/// 聊天面板状态
#[derive(Debug, Clone)]
pub struct ChatPanelState {
    /// 本地 Peer ID（用于区分自己发送的消息）
    local_peer_id: PeerId,
    /// 当前聊天的节点（单个或多个）
    active_chats: Vec<PeerId>,
    /// 当前显示的聊天会话（如果有多个，显示群聊）
    current_chat_index: Option<usize>,
    /// 每个会话的消息历史
    message_history: Vec<(PeerId, ChatMessage)>,
    /// 输入框内容
    input_buffer: String,
    /// 输入框光标位置
    cursor_position: usize,
    /// 消息列表滚动偏移
    scroll_offset: usize,
    /// 是否正在输入（用于发送 TypingIndicator）
    is_typing: bool,
    /// 对方正在输入提示
    peer_typing: Vec<(PeerId, bool)>,
}

impl Default for ChatPanelState {
    fn default() -> Self {
        Self::new(PeerId::random())
    }
}

impl ChatPanelState {
    /// 创建新的聊天面板状态
    pub fn new(local_peer_id: PeerId) -> Self {
        Self {
            local_peer_id,
            active_chats: Vec::new(),
            current_chat_index: None,
            message_history: Vec::new(),
            input_buffer: String::new(),
            cursor_position: 0,
            scroll_offset: 0,
            is_typing: false,
            peer_typing: Vec::new(),
        }
    }

    /// 设置当前聊天的节点
    pub fn set_active_chats(&mut self, peers: Vec<PeerId>) {
        self.active_chats = peers;
        if !self.active_chats.is_empty() {
            self.current_chat_index = Some(0);
        } else {
            self.current_chat_index = None;
        }
    }

    /// 获取当前聊天的节点
    pub fn active_chats(&self) -> &[PeerId] {
        &self.active_chats
    }

    /// 添加消息到历史
    pub fn add_message(&mut self, from: PeerId, message: ChatMessage) {
        self.message_history.push((from, message));

        // 限制历史大小
        while self.message_history.len() > MAX_DISPLAY_MESSAGES {
            self.message_history.remove(0);
        }

        // 自动滚动到底部
        self.scroll_to_bottom();
    }

    /// 获取当前会话的消息历史
    pub fn get_current_history(&self) -> Vec<(PeerId, ChatMessage)> {
        if let Some(index) = self.current_chat_index {
            if let Some(&peer_id) = self.active_chats.get(index) {
                return self
                    .message_history
                    .iter()
                    // 显示：对方发送的消息 + 自己发送的消息（本地 peer_id 在消息中存储）
                    .filter(|(from, _)| *from == peer_id || *from == self.local_peer_id)
                    .cloned()
                    .collect();
            }
        }
        Vec::new()
    }

    /// 处理输入字符
    pub fn handle_input_char(&mut self, c: char) {
        self.input_buffer.insert(self.cursor_position, c);
        self.cursor_position += 1;
        self.is_typing = true;
    }

    /// 处理退格键
    pub fn handle_backspace(&mut self) {
        if self.cursor_position > 0 {
            self.input_buffer.remove(self.cursor_position - 1);
            self.cursor_position -= 1;
        }
    }

    /// 处理删除键
    pub fn handle_delete(&mut self) {
        if self.cursor_position < self.input_buffer.len() {
            self.input_buffer.remove(self.cursor_position);
        }
    }

    /// 处理左移光标
    pub fn move_cursor_left(&mut self) {
        if self.cursor_position > 0 {
            self.cursor_position -= 1;
        }
    }

    /// 处理右移光标
    pub fn move_cursor_right(&mut self) {
        if self.cursor_position < self.input_buffer.len() {
            self.cursor_position += 1;
        }
    }

    /// 移动光标到行首
    pub fn move_cursor_home(&mut self) {
        self.cursor_position = 0;
    }

    /// 移动光标到行尾
    pub fn move_cursor_end(&mut self) {
        self.cursor_position = self.input_buffer.len();
    }

    /// 向上滚动消息列表
    pub fn scroll_up(&mut self) {
        if self.scroll_offset > 0 {
            self.scroll_offset -= 1;
        }
    }

    /// 向下滚动消息列表
    pub fn scroll_down(&mut self) {
        self.scroll_offset += 1;
    }

    /// 滚动到底部
    pub fn scroll_to_bottom(&mut self) {
        self.scroll_offset = self.scroll_offset.saturating_sub(1);
        self.scroll_offset = self.scroll_offset.max(0);
    }

    /// 获取输入框内容并清空
    pub fn take_input(&mut self) -> String {
        self.cursor_position = 0;
        self.is_typing = false;
        std::mem::take(&mut self.input_buffer)
    }

    /// 获取输入框内容（不清空）
    pub fn input(&self) -> &str {
        &self.input_buffer
    }

    /// 设置对方正在输入状态
    pub fn set_peer_typing(&mut self, peer_id: PeerId, is_typing: bool) {
        // 移除旧的记录
        self.peer_typing.retain(|(id, _)| *id != peer_id);
        // 添加新的记录
        if is_typing {
            self.peer_typing.push((peer_id, true));
        }
    }

    /// 获取正在输入的节点
    pub fn get_typing_peers(&self) -> Vec<PeerId> {
        self.peer_typing
            .iter()
            .filter(|(_, is_typing)| *is_typing)
            .map(|(peer_id, _)| *peer_id)
            .collect()
    }

    /// 检查是否有活动聊天
    pub fn has_active_chat(&self) -> bool {
        !self.active_chats.is_empty() && self.current_chat_index.is_some()
    }
}

/// 聊天面板组件
pub struct ChatPanel<'a> {
    /// 聊天面板状态
    pub state: &'a ChatPanelState,
    /// 本地 Peer ID（用于区分自己发送的消息）
    pub local_peer_id: PeerId,
    /// 标题
    pub title: String,
    /// 边框样式
    pub border_style: Style,
    /// 是否有焦点
    pub focused: bool,
}

impl<'a> ChatPanel<'a> {
    /// 创建新的聊天面板
    pub fn new(state: &'a ChatPanelState, local_peer_id: PeerId) -> Self {
        Self {
            state,
            local_peer_id,
            title: "聊天".to_string(),
            border_style: Style::default().fg(Color::Gray),
            focused: false,
        }
    }

    /// 设置标题
    pub fn title(mut self, title: impl Into<String>) -> Self {
        self.title = title.into();
        self
    }

    /// 设置边框样式
    pub fn border_style(mut self, style: Style) -> Self {
        self.border_style = style;
        self
    }

    /// 设置是否有焦点
    pub fn focused(mut self, focused: bool) -> Self {
        self.focused = focused;
        self
    }

    /// 格式化时间戳
    fn format_timestamp(&self, timestamp: i64) -> String {
        use chrono::{DateTime, Local, Utc};
        let dt = DateTime::<Utc>::from_timestamp(timestamp / 1000, 0)
            .unwrap()
            .with_timezone(&Local);
        dt.format("%H:%M").to_string()
    }

    /// 渲染消息列表
    fn render_message_list(&self, area: Rect, buf: &mut Buffer) {
        let messages = self.state.get_current_history();

        if messages.is_empty() {
            // 没有消息时显示提示
            let text = vec![
                Line::from(""),
                Line::from(vec![
                    Span::styled("💬 ", Style::default().fg(Color::Yellow)),
                    Span::styled(
                        "开始聊天",
                        Style::default().fg(Color::White).add_modifier(Modifier::BOLD),
                    ),
                ]),
                Line::from(""),
                Line::from(vec![
                    Span::styled("提示: ", Style::default().fg(Color::Gray)),
                    Span::styled(
                        "选择要聊天的设备，然后在下方输入消息",
                        Style::default().fg(Color::DarkGray),
                    ),
                ]),
            ];

            let paragraph = Paragraph::new(text)
                .alignment(Alignment::Center)
                .wrap(Wrap { trim: true });

            paragraph.render(area, buf);
            return;
        }

        // 逐条渲染消息，根据发送者决定对齐方式
        let mut y = area.top();
        let line_height = 2; // 每条消息占 2 行

        for (from, msg) in messages.iter().skip(self.state.scroll_offset) {
            if y + line_height > area.bottom() {
                break; // 超出显示区域
            }

            if let ChatMessage::Text(text) = msg {
                let is_self = from.to_string() == self.local_peer_id.to_string();
                let timestamp = self.format_timestamp(text.timestamp);
                let prefix = if is_self { "你" } else { "对方" };
                let style = if is_self {
                    Style::default().fg(Color::Cyan)
                } else {
                    Style::default().fg(Color::Green)
                };

                // 构建消息文本
                let message_text = format!("{} {}: {}", timestamp, prefix, text.content);

                // 根据发送者决定对齐方式
                let alignment = if is_self {
                    Alignment::Right
                } else {
                    Alignment::Left
                };

                let msg_area = Rect {
                    x: area.left(),
                    y,
                    width: area.width,
                    height: line_height,
                };

                let paragraph = Paragraph::new(Line::from(vec![
                    Span::styled(message_text, style),
                ]))
                    .alignment(alignment)
                    .wrap(Wrap { trim: true });

                paragraph.render(msg_area, buf);
                y += line_height;
            }
        }
    }

    /// 渲染输入框
    fn render_input_box(&self, area: Rect, buf: &mut Buffer) {
        let input_text = self.state.input();

        // 显示正在输入提示
        let typing_peers = self.state.get_typing_peers();
        let typing_indicator = if typing_peers.is_empty() {
            String::new()
        } else {
            let count = typing_peers.len();
            format!(" ({} 人正在输入...)", count)
        };

        // 构建输入框提示（如果没有活动聊天，显示提示）
        let hint = if !self.state.has_active_chat() {
            " [先选择聊天对象]"
        } else {
            ""
        };

        // 构建输入框文本
        let text = vec![
            Line::from(vec![
                Span::styled(
                    format!("> {}{}{}", input_text, typing_indicator, hint),
                    Style::default().fg(Color::White),
                ),
            ]),
        ];

        let paragraph = Paragraph::new(text)
            .alignment(Alignment::Left);

        paragraph.render(area, buf);
    }
}

impl<'a> Widget for ChatPanel<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        // 先克隆需要移动的值
        let title = self.title.clone();
        let border_style = self.border_style;
        let focused = self.focused;

        // 先渲染外层边框
        let block = Block::default()
            .title(title)
            .borders(Borders::ALL)
            .border_style(if focused {
                Style::default().fg(Color::Green)
            } else {
                border_style
            });
        let inner_area = block.inner(area);
        block.render(area, buf);

        // 在内部区域垂直分割：消息列表 (75%) + 输入框 (25%)
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Percentage(75), Constraint::Percentage(25)])
            .split(inner_area);

        // 渲染消息列表（无内层边框）
        self.render_message_list(chunks[0], buf);

        // 渲染输入框（无内层边框）
        self.render_input_box(chunks[1], buf);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chat_panel_state_creation() {
        let state = ChatPanelState::new();
        assert!(!state.has_active_chat());
        assert!(state.input().is_empty());
        assert_eq!(state.cursor_position, 0);
    }

    #[test]
    fn test_handle_input_char() {
        let mut state = ChatPanelState::new();
        state.handle_input_char('H');
        state.handle_input_char('i');
        assert_eq!(state.input(), "Hi");
        assert_eq!(state.cursor_position, 2);
    }

    #[test]
    fn test_handle_backspace() {
        let mut state = ChatPanelState::new();
        state.handle_input_char('H');
        state.handle_input_char('i');
        state.handle_backspace();
        assert_eq!(state.input(), "H");
        assert_eq!(state.cursor_position, 1);
    }

    #[test]
    fn test_take_input() {
        let mut state = ChatPanelState::new();
        state.handle_input_char('H');
        state.handle_input_char('i');
        let input = state.take_input();
        assert_eq!(input, "Hi");
        assert!(state.input().is_empty());
        assert_eq!(state.cursor_position, 0);
    }

    #[test]
    fn test_set_active_chats() {
        let mut state = ChatPanelState::new();
        let peer_id = PeerId::random();
        state.set_active_chats(vec![peer_id]);
        assert!(state.has_active_chat());
        assert_eq!(state.active_chats().len(), 1);
    }

    #[test]
    fn test_scroll_operations() {
        let mut state = ChatPanelState::new();
        state.scroll_up();
        assert_eq!(state.scroll_offset, 0); // 不能向上滚动
        state.scroll_down();
        assert_eq!(state.scroll_offset, 1);
    }

    #[test]
    fn test_cursor_movement() {
        let mut state = ChatPanelState::new();
        state.handle_input_char('A');
        state.handle_input_char('B');
        state.handle_input_char('C');
        assert_eq!(state.cursor_position, 3);

        state.move_cursor_home();
        assert_eq!(state.cursor_position, 0);

        state.move_cursor_end();
        assert_eq!(state.cursor_position, 3);

        state.move_cursor_left();
        assert_eq!(state.cursor_position, 2);

        state.move_cursor_right();
        assert_eq!(state.cursor_position, 3);
    }
}
