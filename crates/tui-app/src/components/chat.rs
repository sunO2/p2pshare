//! 聊天界面组件
//!
//! 用于和选择的设备进行聊天（占位实现）。

use ratatui::{
    buffer::Buffer,
    layout::{Alignment, Rect},
    style::{Color, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget},
};

/// 聊天组件（占位）
pub struct ChatComponent<'a> {
    /// 消息内容
    pub message: &'a str,
    /// 标题
    pub title: String,
    /// 边框样式
    pub border_style: Style,
}

impl<'a> ChatComponent<'a> {
    /// 创建新的聊天组件
    pub fn new() -> Self {
        Self {
            message: "聊天功能开发中...\n\n敬请期待！",
            title: "聊天".to_string(),
            border_style: Style::default().fg(Color::Blue),
        }
    }

    /// 设置消息
    pub fn message(mut self, message: &'a str) -> Self {
        self.message = message;
        self
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
}

impl<'a> Default for ChatComponent<'a> {
    fn default() -> Self {
        Self::new()
    }
}

impl<'a> Widget for ChatComponent<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let text = vec![
            Line::from(vec![
                Span::styled(
                    "💬 ",
                    Style::default().fg(Color::Yellow),
                ),
                Span::styled(
                    "聊天界面",
                    Style::default().fg(Color::White).add_modifier(ratatui::style::Modifier::BOLD),
                ),
            ]),
            Line::from(""),
            Line::from(self.message),
            Line::from(""),
            Line::from(vec![
                Span::styled("提示: ", Style::default().fg(Color::Gray)),
                Span::styled(
                    "请先在左侧节点列表中选择要聊天的设备",
                    Style::default().fg(Color::DarkGray),
                ),
            ]),
        ];

        let paragraph = Paragraph::new(text)
            .block(
                Block::default()
                    .title(self.title)
                    .borders(Borders::ALL)
                    .border_style(self.border_style),
            )
            .style(Style::default().fg(Color::White))
            .alignment(Alignment::Center);

        paragraph.render(area, buf);
    }
}
