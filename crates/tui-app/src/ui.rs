//! UI 渲染模块
//!
//! 负责整个应用的 UI 渲染。

use crate::components::{ChatPanel, FilePickerComponent, NodeList, AppTab};
use crate::TuiApp;
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

/// 绘制 UI
pub fn draw_ui(f: &mut Frame, app: &TuiApp) {
    // 获取整个区域
    let size = f.area();

    // 主布局：垂直分割（header, body, footer）
    let main_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),  // Header
            Constraint::Min(0),     // Body (flexible)
            Constraint::Length(1),  // Footer
        ])
        .split(size);

    // 绘制 Header
    draw_header(f, main_chunks[0], app);

    // Body 区域：水平分割为三栏（25% | 50% | 25%）
    let body_chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(25),  // 1 设备列表
            Constraint::Percentage(50),  // 2 聊天
            Constraint::Percentage(25),  // 3 文件选择
        ])
        .split(main_chunks[1]);

    // 绘制三个面板
    draw_panel_1_device_list(f, body_chunks[0], app);
    draw_panel_2_chat(f, body_chunks[1], app);
    draw_panel_3_file_picker(f, body_chunks[2], app);

    // 绘制 Footer
    draw_footer(f, main_chunks[2], app);
}

/// 绘制 Header
fn draw_header(f: &mut Frame, area: Rect, app: &TuiApp) {
    let title = Line::from(vec![
        Span::styled(
            "Local P2P",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(" | "),
        Span::styled(
            format!("设备: {}", app.device_name()),
            Style::default().fg(Color::Green),
        ),
    ]);

    let header = Paragraph::new(title)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Blue)),
        )
        .alignment(Alignment::Left);

    f.render_widget(header, area);
}

/// 绘制面板 1：设备列表（上下分栏）
fn draw_panel_1_device_list(f: &mut Frame, area: Rect, app: &TuiApp) {
    // 垂直分割：上部分设备列表，下部分节点信息
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage(60),  // 设备列表
            Constraint::Percentage(40),  // 节点信息
        ])
        .split(area);

    // 判断是否有焦点
    let has_focus = app.current_tab() == AppTab::Panel1;
    let border_style = if has_focus {
        Style::default().fg(Color::Green)
    } else {
        Style::default().fg(Color::DarkGray)
    };

    // 上部分：设备列表
    let node_list = NodeList::new(app.node_list_state())
        .title(if has_focus { "[1] 设备列表 *" } else { "[1] 设备列表" })
        .detailed(false)
        .border_style(border_style);
    f.render_widget(node_list, chunks[0]);

    // 下部分：当前节点信息
    draw_current_node_info(f, chunks[1], app, has_focus);
}

/// 绘制当前节点信息
fn draw_current_node_info(f: &mut Frame, area: Rect, app: &TuiApp, has_focus: bool) {
    let title = "当前选中设备";
    let border_style = if has_focus {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default().fg(Color::DarkGray)
    };

    if let Some(details) = app.selected_node_details() {
        let details_paragraph = Paragraph::new(details)
            .block(
                Block::default()
                    .title(title)
                    .borders(Borders::ALL)
                    .border_style(border_style),
            )
            .style(Style::default().fg(Color::White));

        f.render_widget(details_paragraph, area);
    } else {
        let empty_text = vec![
            Line::from("未选择设备"),
            Line::from(""),
            Line::from("使用 ↑↓ 键选择设备"),
        ];

        let empty_paragraph = Paragraph::new(empty_text)
            .block(
                Block::default()
                    .title(title)
                    .borders(Borders::ALL)
                    .border_style(border_style),
            )
            .style(Style::default().fg(Color::Gray))
            .alignment(Alignment::Center);

        f.render_widget(empty_paragraph, area);
    }
}

/// 绘制面板 2：聊天
fn draw_panel_2_chat(f: &mut Frame, area: Rect, app: &TuiApp) {
    let has_focus = app.current_tab() == AppTab::Panel2;

    // 使用 ChatPanel 组件（包含消息列表和输入框）
    let chat_panel = ChatPanel::new(app.chat_panel_state(), app.local_peer_id())
        .title(if has_focus { "[2] 聊天 *" } else { "[2] 聊天" })
        .border_style(if has_focus {
            Style::default().fg(Color::Green)
        } else {
            Style::default().fg(Color::DarkGray)
        })
        .focused(has_focus);

    f.render_widget(chat_panel, area);
}

/// 绘制面板 3：文件选择
fn draw_panel_3_file_picker(f: &mut Frame, area: Rect, app: &TuiApp) {
    let selected_node = app.node_list_state().get_current();
    let has_focus = app.current_tab() == AppTab::Panel3;
    let border_style = if has_focus {
        Style::default().fg(Color::Green)
    } else {
        Style::default().fg(Color::DarkGray)
    };

    if selected_node.is_some() {
        let node = selected_node.unwrap();
        let msg = format!("选择文件分享给 {}", node.display_name);
        let title = if has_focus { "[3] 文件选择 *" } else { "[3] 文件选择" };
        let file_picker = FilePickerComponent::new().message(msg.as_str()).title(title).border_style(border_style);
        f.render_widget(file_picker, area);
    } else {
        let hint_text = vec![
            Line::from("文件选择"),
            Line::from(""),
            Line::from("请先在设备列表中选择要分享文件的设备"),
        ];

        let title = if has_focus { "[3] 文件选择 *" } else { "[3] 文件选择" };
        let hint_paragraph = Paragraph::new(hint_text)
            .block(
                Block::default()
                    .title(title)
                    .borders(Borders::ALL)
                    .border_style(border_style),
            )
            .style(Style::default().fg(Color::White))
            .alignment(Alignment::Center);

        f.render_widget(hint_paragraph, area);
    }
}

/// 绘制 Footer
fn draw_footer(f: &mut Frame, area: Rect, app: &TuiApp) {
    let (focus_indicator, help_keys) = match app.current_tab() {
        AppTab::Panel1 => ("设备列表", "[↑↓] 选择 [Space/Enter] 选中"),
        AppTab::Panel2 => ("聊天", "[输入文字] 打字 [Enter] 发送 [↑↓] 滚动"),
        AppTab::Panel3 => ("文件选择", "[↑↓] 选择 [Enter] 打开"),
    };
    let help_text = format!(
        "[Tab] 切换焦点 | 当前焦点: {} | {} | [q] 退出",
        focus_indicator, help_keys
    );

    let footer = Paragraph::new(help_text)
        .style(Style::default().fg(Color::Gray))
        .alignment(Alignment::Center);

    f.render_widget(footer, area);
}
