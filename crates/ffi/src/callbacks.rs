//! 回调函数管理
//!
//! 处理从 Rust 到 Dart/Flutter 的回调

use std::sync::{Mutex, OnceLock};
use std::ffi::c_void;
use libc::c_char;

use crate::types::*;

/// 事件回调函数类型
///
/// # Parameters
/// * `event` - 事件数据
/// * `user_data` - 用户提供的上下文数据
pub type EventCallback = extern "C" fn(event: P2PEventData, user_data: *mut c_void);

/// 线程安全的回调数据
struct CallbackData {
    callback: EventCallback,
    user_data: *mut c_void,
}

// 实现 Send（裸指针不是 Send，但我们只在同一线程中使用）
unsafe impl Send for CallbackData {}

/// 全局回调函数和用户数据
static CALLBACK: Mutex<OnceLock<CallbackData>> = Mutex::new(OnceLock::new());

/// 设置事件回调
///
/// # Safety
/// user_data 必须是有效的指针，直到回调被清除
pub unsafe fn set_event_callback(callback: EventCallback, user_data: *mut c_void) {
    let cb = CALLBACK.lock().unwrap();
    let data = CallbackData {
        callback,
        user_data,
    };
    let _ = cb.set(data);
}

/// 清除事件回调
pub fn clear_event_callback() {
    let mut cb = CALLBACK.lock().unwrap();
    *cb = OnceLock::new();
}

/// 触发事件回调
pub fn trigger_event_callback(event: P2PEventData) {
    let cb = CALLBACK.lock().unwrap();
    if let Some(data) = cb.get() {
        (data.callback)(event, data.user_data);
    }
}

/// 创建 P2PEventData（用于触发回调）
pub fn create_event_data(
    event_type: P2PEventType,
    peer_id: Option<&str>,
    display_name: Option<&str>,
    message: Option<&str>,
    message_id: Option<&str>,
    is_typing: bool,
    timestamp: i64,
) -> P2PEventData {
    P2PEventData {
        event_type,
        peer_id: peer_id.map(|s| s.as_ptr() as *const c_char).unwrap_or(std::ptr::null()),
        display_name: display_name.map(|s| s.as_ptr() as *const c_char).unwrap_or(std::ptr::null()),
        message: message.map(|s| s.as_ptr() as *const c_char).unwrap_or(std::ptr::null()),
        message_id: message_id.map(|s| s.as_ptr() as *const c_char).unwrap_or(std::ptr::null()),
        is_typing,
        timestamp,
    }
}
