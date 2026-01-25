//! TUI 应用模块
//!
//! 提供基于 Ratatui 的终端用户界面，用于可视化管理 P2P 节点。

pub mod app;
pub mod event;
pub mod ui;
pub mod components;

pub use app::TuiApp;
pub use event::{Event, EventHandler, AppResult};

/// 运行 TUI 应用的便捷函数
pub use app::run_tui;
