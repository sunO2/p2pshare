//! 文件选择组件
//!
//! 用于选择文件进行分享（占位实现）。

use ratatui::{
    buffer::Buffer,
    layout::{Alignment, Rect},
    style::{Color, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget},
};

/// 文件选择组件（占位）
pub struct FilePickerComponent<'a> {
    /// 消息内容
    pub message: &'a str,
    /// 标题
    pub title: String,
    /// 边框样式
    pub border_style: Style,
}

impl<'a> FilePickerComponent<'a> {
    /// 创建新的文件选择组件
    pub fn new() -> Self {
        Self {
            message: "文件选择功能开发中...\n\n敬请期待！",
            title: "文件选择".to_string(),
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

impl<'a> Default for FilePickerComponent<'a> {
    fn default() -> Self {
        Self::new()
    }
}

impl<'a> Widget for FilePickerComponent<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let text = vec![
            Line::from(vec![
                Span::styled(
                    "📁 ",
                    Style::default().fg(Color::Yellow),
                ),
                Span::styled(
                    "文件选择",
                    Style::default().fg(Color::White).add_modifier(ratatui::style::Modifier::BOLD),
                ),
            ]),
            Line::from(""),
            Line::from(self.message),
            Line::from(""),
            Line::from(vec![
                Span::styled("提示: ", Style::default().fg(Color::Gray)),
                Span::styled(
                    "请先在左侧节点列表中选择要分享文件的设备",
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
