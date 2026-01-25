//! Tab 切换组件
//!
//! 管理 Tab 切换和渲染。

use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Style},
    widgets::{Tabs as RatatuiTabs, Widget},
};

/// 面板类型（用于焦点切换）
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AppTab {
    Panel1,     // 设备列表
    Panel2,     // 聊天
    Panel3,     // 文件选择
}

impl AppTab {
    pub fn title(&self) -> &str {
        match self {
            AppTab::Panel1 => "[1] 设备列表",
            AppTab::Panel2 => "[2] 聊天",
            AppTab::Panel3 => "[3] 文件选择",
        }
    }

    pub fn all() -> &'static [AppTab] {
        &[AppTab::Panel1, AppTab::Panel2, AppTab::Panel3]
    }

    pub fn index(&self) -> usize {
        match self {
            AppTab::Panel1 => 0,
            AppTab::Panel2 => 1,
            AppTab::Panel3 => 2,
        }
    }

    pub fn from_index(index: usize) -> Option<Self> {
        match index {
            0 => Some(AppTab::Panel1),
            1 => Some(AppTab::Panel2),
            2 => Some(AppTab::Panel3),
            _ => None,
        }
    }

    pub fn next(&self) -> Self {
        match self {
            AppTab::Panel1 => AppTab::Panel2,
            AppTab::Panel2 => AppTab::Panel3,
            AppTab::Panel3 => AppTab::Panel1,
        }
    }

    pub fn previous(&self) -> Self {
        match self {
            AppTab::Panel1 => AppTab::Panel3,
            AppTab::Panel2 => AppTab::Panel1,
            AppTab::Panel3 => AppTab::Panel2,
        }
    }
}

/// Tab 组件
pub struct Tabs {
    /// 当前选中的 Tab
    pub current: AppTab,
}

impl Tabs {
    /// 创建新的 Tab 组件
    pub fn new(current: AppTab) -> Self {
        Self { current }
    }

    /// 设置当前 Tab
    pub fn set_current(&mut self, tab: AppTab) {
        self.current = tab;
    }

    /// 切换到下一个 Tab
    pub fn next(&mut self) {
        self.current = self.current.next();
    }

    /// 切换到上一个 Tab
    pub fn previous(&mut self) {
        self.current = self.current.previous();
    }

    /// 获取所有 Tab 标题
    fn titles(&self) -> Vec<String> {
        AppTab::all()
            .iter()
            .map(|t| t.title().to_string())
            .collect()
    }
}

impl Widget for Tabs {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let titles = self.titles();
        let index = self.current.index();

        let tabs = RatatuiTabs::new(titles)
            .block(
                ratatui::widgets::Block::default()
                    .borders(ratatui::widgets::Borders::ALL)
                    .border_style(Style::default().fg(Color::Blue)),
            )
            .style(Style::default().fg(Color::White))
            .highlight_style(
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(ratatui::style::Modifier::BOLD),
            )
            .select(index)
            .divider(" | ");

        tabs.render(area, buf);
    }
}
