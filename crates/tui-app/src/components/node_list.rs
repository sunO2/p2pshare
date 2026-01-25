//! 节点列表组件
//!
//! 显示已验证的节点列表，支持单选和多选。

use libp2p::PeerId;
use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, List, ListItem, Widget},
};
use std::collections::HashSet;

/// 节点列表项
#[derive(Debug, Clone)]
pub struct NodeItem {
    pub peer_id: PeerId,
    pub display_name: String,
    pub device_name: String,
    pub status: NodeStatus,
    pub addresses: Vec<String>,
}

/// 节点状态
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NodeStatus {
    Online,
    Offline,
    Unknown,
}

impl NodeStatus {
    pub fn as_str(&self) -> &str {
        match self {
            NodeStatus::Online => "在线",
            NodeStatus::Offline => "离线",
            NodeStatus::Unknown => "未知",
        }
    }

    pub fn color(&self) -> Color {
        match self {
            NodeStatus::Online => Color::Green,
            NodeStatus::Offline => Color::Red,
            NodeStatus::Unknown => Color::Gray,
        }
    }
}

/// 节点列表状态
#[derive(Debug, Clone)]
pub struct NodeListState {
    /// 节点列表
    pub items: Vec<NodeItem>,
    /// 多选索引集合
    pub selected: HashSet<usize>,
    /// 光标位置
    pub cursor: usize,
}

impl Default for NodeListState {
    fn default() -> Self {
        Self {
            items: Vec::new(),
            selected: HashSet::new(),
            cursor: 0,
        }
    }
}

impl NodeListState {
    /// 创建新的节点列表状态
    pub fn new(items: Vec<NodeItem>) -> Self {
        let cursor = if items.is_empty() { 0 } else { items.len() - 1 };
        Self {
            items,
            selected: HashSet::new(),
            cursor,
        }
    }

    /// 切换选中状态
    pub fn toggle_selection(&mut self) {
        if self.cursor < self.items.len() {
            if !self.selected.remove(&self.cursor) {
                self.selected.insert(self.cursor);
            }
        }
    }

    /// 设置单选
    pub fn set_single_selection(&mut self) {
        self.selected.clear();
        if self.cursor < self.items.len() {
            self.selected.insert(self.cursor);
        }
    }

    /// 获取选中项
    pub fn get_selected(&self) -> Vec<&NodeItem> {
        self.selected
            .iter()
            .filter_map(|&i| self.items.get(i))
            .collect()
    }

    /// 获取选中节点的 Peer ID 列表
    pub fn get_selected_peer_ids(&self) -> Vec<PeerId> {
        self.selected
            .iter()
            .filter_map(|&i| self.items.get(i))
            .map(|node| node.peer_id)
            .collect()
    }

    /// 获取当前光标项
    pub fn get_current(&self) -> Option<&NodeItem> {
        self.items.get(self.cursor)
    }

    /// 移动光标向上
    pub fn move_up(&mut self) {
        if !self.items.is_empty() && self.cursor > 0 {
            self.cursor -= 1;
        }
    }

    /// 移动光标向下
    pub fn move_down(&mut self) {
        if !self.items.is_empty() && self.cursor < self.items.len() - 1 {
            self.cursor += 1;
        }
    }

    /// 添加节点
    pub fn add_node(&mut self, node: NodeItem) {
        self.items.push(node);
    }

    /// 移除节点
    pub fn remove_node(&mut self, peer_id: &PeerId) {
        if let Some(pos) = self.items.iter().position(|n| n.peer_id == *peer_id) {
            self.items.remove(pos);
            // 调整选中的索引
            self.selected = self
                .selected
                .iter()
                .map(|&i| if i > pos { i - 1 } else { i })
                .collect();
            // 调整光标
            if self.cursor >= self.items.len() && !self.items.is_empty() {
                self.cursor = self.items.len() - 1;
            }
        }
    }

    /// 更新节点
    pub fn update_node(&mut self, peer_id: &PeerId, mut f: impl FnMut(&mut NodeItem)) {
        if let Some(node) = self.items.iter_mut().find(|n| n.peer_id == *peer_id) {
            f(node);
        }
    }
}

/// 节点列表组件
pub struct NodeList<'a> {
    /// 列表状态
    pub state: &'a NodeListState,
    /// 标题
    pub title: String,
    /// 是否显示详细信息
    pub detailed: bool,
    /// 边框样式
    pub border_style: Style,
}

impl<'a> NodeList<'a> {
    /// 创建新的节点列表
    pub fn new(state: &'a NodeListState) -> Self {
        Self {
            state,
            title: "节点列表".to_string(),
            detailed: false,
            border_style: Style::default().fg(Color::Blue),
        }
    }

    /// 设置标题
    pub fn title(mut self, title: impl Into<String>) -> Self {
        self.title = title.into();
        self
    }

    /// 设置是否显示详细信息
    pub fn detailed(mut self, detailed: bool) -> Self {
        self.detailed = detailed;
        self
    }

    /// 设置边框样式
    pub fn border_style(mut self, style: Style) -> Self {
        self.border_style = style;
        self
    }
}

impl<'a> Widget for NodeList<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        // 创建列表项
        let items: Vec<ListItem> = self
            .state
            .items
            .iter()
            .enumerate()
            .map(|(i, node)| {
                let is_selected = self.state.selected.contains(&i);
                let is_cursor = i == self.state.cursor;
                let checkbox = if is_selected {
                    "[✓]"
                } else {
                    "[ ]"
                };
                let cursor = if is_cursor { ">" } else { " " };

                if self.detailed {
                    // 详细模式
                    ListItem::new(format!(
                        "{} {} {}\n   状态: {}\n   地址: {}",
                        cursor,
                        checkbox,
                        node.display_name,
                        node.status.as_str(),
                        node.addresses.first().map(|s| s.as_str()).unwrap_or("无")
                    ))
                } else {
                    // 简洁模式
                    ListItem::new(format!(
                        "{} {} {} ({})",
                        cursor,
                        checkbox,
                        node.display_name,
                        node.device_name
                    ))
                }
            })
            .collect();

        // 创建列表样式
        let list_style = Style::default().fg(Color::White);

        // 创建列表
        let list = List::new(items)
            .block(
                Block::default()
                    .title(self.title)
                    .borders(Borders::ALL)
                    .border_style(self.border_style),
            )
            .style(list_style)
            .highlight_style(
                Style::default()
                    .bg(Color::DarkGray)
                    .add_modifier(Modifier::BOLD),
            )
            .highlight_symbol("> ");

        // 渲染列表
        // Note: ratatui 0.29 的 Widget::render 只接受 2 个参数
        list.render(area, buf);
    }
}
