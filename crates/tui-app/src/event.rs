//! 事件处理模块
//!
//! 处理键盘输入和异步事件。

use crossterm::event::{KeyEvent, KeyEventKind};
use futures::StreamExt;
use mdns::{ManagedDiscoveryEvent, MdnsError, ChatEvent};
use std::time::Duration;

/// 应用事件
#[derive(Debug, Clone)]
pub enum Event {
    /// 键盘输入事件
    Input(KeyEvent),
    /// 发现事件
    Discovery(ManagedDiscoveryEvent),
    /// 聊天事件
    Chat(ChatEvent),
    /// 定时刷新事件
    Tick,
}

/// 事件处理器
pub struct EventHandler {
    /// 事件发送器
    pub tx: tokio::sync::mpsc::Sender<Event>,
}

impl EventHandler {
    /// 创建新的事件处理器
    pub fn new(tx: tokio::sync::mpsc::Sender<Event>) -> Self {
        Self { tx }
    }

    /// 启动键盘输入监听
    pub async fn run_keyboard_listener(&self) -> AppResult<()> {
        let mut reader = crossterm::event::EventStream::new();

        while let Some(event) = reader.next().await {
            match event {
                Ok(crossterm::event::Event::Key(key_event)) => {
                    // 只处理按键按下事件，忽略重复和释放事件
                    if key_event.kind == KeyEventKind::Press {
                        self.tx.send(Event::Input(key_event)).await?;
                    }
                }
                Ok(_) => {
                    // 忽略其他事件（如鼠标、调整大小等）
                }
                Err(err) => {
                    tracing::error!("键盘事件错误: {:?}", err);
                    return Err(AppError::Io(err));
                }
            }
        }

        Ok(())
    }

    /// 启动定时器
    pub async fn run_ticker(&self, tick_rate: Duration) -> AppResult<()> {
        let mut interval = tokio::time::interval(tick_rate);

        loop {
            interval.tick().await;
            self.tx.send(Event::Tick).await?;
        }
    }
}

/// 应用错误类型
#[derive(Debug)]
pub enum AppError {
    Io(std::io::Error),
    Send(String),
    Mdns(String),
}

impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AppError::Io(err) => write!(f, "IO 错误: {}", err),
            AppError::Send(err) => write!(f, "发送错误: {}", err),
            AppError::Mdns(err) => write!(f, "mDNS 错误: {}", err),
        }
    }
}

impl std::error::Error for AppError {}

impl From<std::io::Error> for AppError {
    fn from(err: std::io::Error) -> Self {
        AppError::Io(err)
    }
}

impl From<tokio::sync::mpsc::error::SendError<Event>> for AppError {
    fn from(err: tokio::sync::mpsc::error::SendError<Event>) -> Self {
        AppError::Send(err.to_string())
    }
}

impl From<MdnsError> for AppError {
    fn from(err: MdnsError) -> Self {
        AppError::Mdns(err.to_string())
    }
}

/// 应用结果类型
pub type AppResult<T> = Result<T, AppError>;
