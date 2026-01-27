//! 回调函数管理
//!
//! 使用线程安全的方式从 Rust 后台线程向 Dart isolate 发送事件

use std::sync::{Mutex, OnceLock};
use std::ffi::c_void;

use crate::types::*;

/// 事件回调函数类型（线程安全）
///
/// # Parameters
/// * `event_type` - 事件类型
/// * `data_json` - 事件数据的 JSON 字符串
pub type EventCallbackSimple = extern "C" fn(event_type: i32, data_json: *const i8);

/// 全局回调函数
static CALLBACK: Mutex<OnceLock<EventCallbackSimple>> = Mutex::new(OnceLock::new());

/// 设置事件回调（从 Dart 调用）
///
/// # Safety
/// callback 必须是有效的函数指针
pub unsafe fn set_event_callback_simple(callback: EventCallbackSimple) {
    let cb = CALLBACK.lock().unwrap();
    let _ = cb.set(callback);
    tracing::info!("Event callback set");
}

/// 清除事件回调
pub fn clear_event_callback() {
    let mut cb = CALLBACK.lock().unwrap();
    *cb = OnceLock::new();
}

/// 发送事件到 Dart（线程安全）
pub fn send_event_to_dart(event_type: i32, data_json: &str) {
    let cb = CALLBACK.lock().unwrap();
    if let Some(callback) = cb.get() {
        // 将 JSON 字符串转换为 C 字符串
        if let Ok(c_str) = std::ffi::CString::new(data_json) {
            let ptr = c_str.as_ptr();
            // 调用回调（转换 *const u8 为 *const i8）
            callback(event_type, ptr as *const i8);
            // c_str 会在作用域结束时自动释放
        } else {
            tracing::error!("Failed to create CString: invalid UTF-8");
        }
    } else {
        tracing::warn!("Event callback not set, skipping event type {}", event_type);
    }
}

/// 触发事件回调（兼容旧接口）
pub fn trigger_event_callback(event: P2PEventData) {
    use crate::types::P2PEventType;
    use std::ffi::CStr;

    // 将事件转换为 JSON 字符串
    let peer_id = unsafe {
        if !event.peer_id.is_null() {
            CStr::from_ptr(event.peer_id).to_string_lossy().to_string()
        } else {
            String::new()
        }
    };

    let display_name = unsafe {
        if !event.display_name.is_null() {
            CStr::from_ptr(event.display_name).to_string_lossy().to_string()
        } else {
            String::new()
        }
    };

    let data_json = format!(
        r#"{{"peer_id":"{}","display_name":"{}"}}"#,
        peer_id, display_name
    );

    send_event_to_dart(event.event_type as i32, &data_json);
}
