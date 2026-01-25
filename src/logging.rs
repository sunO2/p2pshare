//! 日志配置模块
//!
//! 提供日志到文件的输出配置。

use tracing_appender::{non_blocking, rolling};
use tracing_subscriber::{
    fmt,
    layer::{Layer, SubscriberExt},
    util::SubscriberInitExt,
    filter::LevelFilter,
};
use std::path::PathBuf;

/// 日志文件前缀
const LOG_FILE_PREFIX: &str = "localp2p";

/// 日志级别
#[derive(Debug, Clone, Copy)]
#[allow(dead_code)]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

impl LogLevel {
    fn to_tracing_level(self) -> tracing::Level {
        match self {
            LogLevel::Trace => tracing::Level::TRACE,
            LogLevel::Debug => tracing::Level::DEBUG,
            LogLevel::Info => tracing::Level::INFO,
            LogLevel::Warn => tracing::Level::WARN,
            LogLevel::Error => tracing::Level::ERROR,
        }
    }
}

impl Default for LogLevel {
    fn default() -> Self {
        LogLevel::Info
    }
}

/// 日志配置
#[derive(Debug, Clone)]
pub struct LoggingConfig {
    /// 日志目录
    pub log_dir: PathBuf,
    /// 日志级别
    pub level: LogLevel,
    /// 是否同时输出到控制台
    pub console_output: bool,
    /// 是否使用颜色（仅控制台）
    pub ansi: bool,
}

impl Default for LoggingConfig {
    fn default() -> Self {
        Self {
            log_dir: PathBuf::from("logs"),
            level: LogLevel::default(),
            console_output: false,
            ansi: false,
        }
    }
}

impl LoggingConfig {
    /// 创建新的日志配置
    pub fn new() -> Self {
        Self::default()
    }

    /// 设置日志目录
    #[allow(dead_code)]
    pub fn with_log_dir(mut self, dir: impl Into<PathBuf>) -> Self {
        self.log_dir = dir.into();
        self
    }

    /// 设置日志级别
    pub fn with_level(mut self, level: LogLevel) -> Self {
        self.level = level;
        self
    }

    /// 设置是否输出到控制台
    pub fn with_console_output(mut self, output: bool) -> Self {
        self.console_output = output;
        self
    }

    /// 设置是否使用 ANSI 颜色
    pub fn with_ansi(mut self, ansi: bool) -> Self {
        self.ansi = ansi;
        self
    }

    /// 初始化日志系统
    ///
    /// 此函数应该只调用一次，通常在 main 函数的开头。
    pub fn init(self) -> Result<(), Box<dyn std::error::Error>> {
        // 确保日志目录存在
        std::fs::create_dir_all(&self.log_dir)?;

        // 创建滚动文件 appender（每天一个文件）
        let file_appender = rolling::daily(self.log_dir, LOG_FILE_PREFIX);
        let (non_blocking_file, _guard) = non_blocking(file_appender);

        // 构建订阅者
        let subscriber = tracing_subscriber::registry();

        // 添加文件层
        let file_layer = fmt::layer()
            .with_writer(non_blocking_file)
            .with_ansi(false)
            .with_level(true)
            .with_target(true)
            .with_thread_ids(false)
            .with_thread_names(false)
            .with_file(false)
            .with_line_number(false)
            .with_filter(LevelFilter::from(self.level.to_tracing_level()));

        let subscriber = subscriber.with(file_layer);

        // 如果需要，添加控制台层
        if self.console_output {
            let console_layer = fmt::layer()
                .with_writer(std::io::stdout)
                .with_ansi(self.ansi)
                .with_level(true)
                .with_target(true)
                .with_filter(LevelFilter::from(self.level.to_tracing_level()));

            subscriber.with(console_layer).init();
        } else {
            subscriber.init();
        }

        // 注意：_guard 必须保持存活，否则日志会停止写入
        // 由于这是一个全局初始化函数，我们无法返回 guard
        // 所以我们使用 std::mem::forget 来防止 guard 被释放
        // 这是一个已知的模式，用于全局日志配置
        std::mem::forget(_guard);

        Ok(())
    }
}

/// 简单的日志初始化函数
///
/// 使用默认配置初始化日志系统，输出到 `logs/` 目录。
#[allow(dead_code)]
pub fn init_logging() -> Result<(), Box<dyn std::error::Error>> {
    LoggingConfig::new().init()
}

/// 自定义日志级别的初始化
#[allow(dead_code)]
pub fn init_logging_with_level(level: LogLevel) -> Result<(), Box<dyn std::error::Error>> {
    LoggingConfig::new().with_level(level).init()
}

/// 同时输出到文件和控制台的初始化
pub fn init_logging_with_console(
    level: LogLevel,
) -> Result<(), Box<dyn std::error::Error>> {
    LoggingConfig::new()
        .with_level(level)
        .with_console_output(true)
        .with_ansi(true)
        .init()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_log_level_conversion() {
        assert_eq!(LogLevel::Trace.to_tracing_level(), tracing::Level::TRACE);
        assert_eq!(LogLevel::Debug.to_tracing_level(), tracing::Level::DEBUG);
        assert_eq!(LogLevel::Info.to_tracing_level(), tracing::Level::INFO);
        assert_eq!(LogLevel::Warn.to_tracing_level(), tracing::Level::WARN);
        assert_eq!(LogLevel::Error.to_tracing_level(), tracing::Level::ERROR);
    }

    #[test]
    fn test_config_builder() {
        let config = LoggingConfig::new()
            .with_log_dir("/tmp/logs")
            .with_level(LogLevel::Debug)
            .with_console_output(true)
            .with_ansi(true);

        assert_eq!(config.log_dir, PathBuf::from("/tmp/logs"));
        assert_eq!(config.level, LogLevel::Debug);
        assert_eq!(config.console_output, true);
        assert_eq!(config.ansi, true);
    }
}
