/**
 * @file localp2p.h
 * @brief Local P2P FFI 接口头文件
 *
 * 提供 C ABI 兼容的接口，用于 Flutter/Dart 等外部调用
 */

#ifndef LOCALP2P_H
#define LOCALP2P_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

/* ==========================================================================
 * 类型定义
 * ========================================================================== */

/**
 * @brief P2P 不透明句柄
 *
 * 用于标识 P2P 实例，调用者不应直接访问其内部字段
 */
typedef struct {
    int32_t _private;
} LocalP2P_Handle;

/**
 * @brief P2P 错误代码
 */
typedef enum {
    /** 成功 */
    LOCALP2P_SUCCESS = 0,
    /** 未初始化 */
    LOCALP2P_NOT_INITIALIZED = -1,
    /** 无效参数 */
    LOCALP2P_INVALID_ARGUMENT = -2,
    /** 发送失败 */
    LOCALP2P_SEND_FAILED = -3,
    /** 节点未验证 */
    LOCALP2P_NODE_NOT_VERIFIED = -4,
    /** 内存不足 */
    LOCALP2P_OUT_OF_MEMORY = -5,
    /** 其他错误 */
    LOCALP2P_UNKNOWN = -99,
} LocalP2P_ErrorCode;

/**
 * @brief P2P 事件类型
 */
typedef enum {
    /** 节点发现 */
    LOCALP2P_EVENT_NODE_DISCOVERED = 1,
    /** 节点过期 */
    LOCALP2P_EVENT_NODE_EXPIRED = 2,
    /** 节点验证 */
    LOCALP2P_EVENT_NODE_VERIFIED = 3,
    /** 节点离线 */
    LOCALP2P_EVENT_NODE_OFFLINE = 4,
    /** 收到用户信息 */
    LOCALP2P_EVENT_USER_INFO_RECEIVED = 5,
    /** 收到消息 */
    LOCALP2P_EVENT_MESSAGE_RECEIVED = 6,
    /** 消息已发送 */
    LOCALP2P_EVENT_MESSAGE_SENT = 7,
    /** 正在输入 */
    LOCALP2P_EVENT_PEER_TYPING = 8,
} LocalP2P_EventType;

/**
 * @brief P2P 事件数据
 *
 * 传递给事件回调函数的数据结构
 * 注意：字符串指针仅在回调期间有效
 */
typedef struct {
    /** 事件类型 */
    LocalP2P_EventType event_type;
    /** Peer ID（事件相关的节点 ID，仅在回调期间有效）*/
    const char *peer_id;
    /** 显示名称（对于 NodeVerified 事件，仅在回调期间有效）*/
    const char *display_name;
    /** 消息内容（对于 MessageReceived 事件，仅在回调期间有效）*/
    const char *message;
    /** 消息 ID（对于 MessageSent 事件，仅在回调期间有效）*/
    const char *message_id;
    /** 是否正在输入（对于 PeerTyping 事件）*/
    bool is_typing;
    /** 时间戳（对于消息事件，Unix 毫秒时间戳）*/
    int64_t timestamp;
} LocalP2P_EventData;

/**
 * @brief 节点信息
 *
 * 返回的节点详细信息
 * 调用者需要使用 localp2p_free_node_info() 释放
 */
typedef struct {
    /** Peer ID（UTF-8 字符串，需要释放）*/
    char *peer_id;
    /** 显示名称（UTF-8 字符串，需要释放）*/
    char *display_name;
    /** 设备名称（UTF-8 字符串，需要释放）*/
    char *device_name;
    /** 地址数量 */
    size_t address_count;
    /** 地址数组（需要释放每个字符串和数组本身）*/
    char **addresses;
} LocalP2P_NodeInfo;

/**
 * @brief 事件回调函数类型
 *
 * @param event 事件数据
 * @param user_data 用户提供的上下文数据
 */
typedef void (*LocalP2P_EventCallback)(LocalP2P_EventData event, void *user_data);

/* ==========================================================================
 * 核心函数
 * ========================================================================== */

/**
 * @brief 初始化 P2P 模块
 *
 * @param device_name 设备名称（UTF-8 字符串）
 * @param error_out 错误信息输出（如果失败，需要调用 localp2p_free_error 释放）
 * @return P2P 句柄（如果失败，返回的句柄无效）
 *
 * @note 必须在使用任何其他函数之前调用，且只能调用一次
 */
LocalP2P_Handle localp2p_init(const char *device_name, char **error_out);

/**
 * @brief 启动 P2P 服务并开始发现节点
 *
 * @param handle P2P 句柄（由 localp2p_init 返回）
 * @param event_callback 事件回调函数
 * @param user_data 用户数据（会传递给回调函数）
 * @return 错误代码（LOCALP2P_SUCCESS 表示成功）
 *
 * @note 必须在 localp2p_init 之后调用
 */
LocalP2P_ErrorCode localp2p_start(LocalP2P_Handle handle,
                                   LocalP2P_EventCallback event_callback,
                                   void *user_data);

/**
 * @brief 停止 P2P 服务
 *
 * @param handle P2P 句柄
 * @return 错误代码（LOCALP2P_SUCCESS 表示成功）
 */
LocalP2P_ErrorCode localp2p_stop(LocalP2P_Handle handle);

/**
 * @brief 清理资源
 *
 * @param handle P2P 句柄
 *
 * @note 清理后，handle 将失效
 */
void localp2p_cleanup(LocalP2P_Handle handle);

/* ==========================================================================
 * 查询函数
 * ========================================================================== */

/**
 * @brief 获取本地 Peer ID
 *
 * @param handle P2P 句柄
 * @param out 输出缓冲区
 * @param out_len 缓冲区大小
 * @return 错误代码（LOCALP2P_SUCCESS 表示成功）
 */
LocalP2P_ErrorCode localp2p_get_local_peer_id(LocalP2P_Handle handle,
                                              char *out,
                                              size_t out_len);

/**
 * @brief 获取设备名称
 *
 * @param handle P2P 句柄
 * @param out 输出缓冲区
 * @param out_len 缓冲区大小
 * @return 错误代码（LOCALP2P_SUCCESS 表示成功）
 */
LocalP2P_ErrorCode localp2p_get_device_name(LocalP2P_Handle handle,
                                            char *out,
                                            size_t out_len);

/**
 * @brief 获取已验证的节点列表
 *
 * @param handle P2P 句柄
 * @param out 输出节点列表数组
 * @param out_len 输出节点数量
 * @return 错误代码（LOCALP2P_SUCCESS 表示成功）
 *
 * @note 调用者必须使用 localp2p_free_node_list() 释放返回的数组
 */
LocalP2P_ErrorCode localp2p_get_verified_nodes(LocalP2P_Handle handle,
                                               LocalP2P_NodeInfo **out,
                                               size_t *out_len);

/**
 * @brief 释放节点列表
 *
 * @param nodes 节点列表数组
 * @param len 节点数量
 */
void localp2p_free_node_list(LocalP2P_NodeInfo *nodes, size_t len);

/* ==========================================================================
 * 聊天功能
 * ========================================================================== */

/**
 * @brief 发送消息给指定节点
 *
 * @param handle P2P 句柄
 * @param target_peer_id 目标节点 Peer ID（UTF-8 字符串）
 * @param message 消息内容（UTF-8 字符串）
 * @param error_out 错误信息输出（如果失败，需要调用 localp2p_free_error 释放）
 * @return 错误代码（LOCALP2P_SUCCESS 表示成功）
 */
LocalP2P_ErrorCode localp2p_send_message(LocalP2P_Handle handle,
                                         const char *target_peer_id,
                                         const char *message,
                                         char **error_out);

/**
 * @brief 广播消息给多个节点
 *
 * @param handle P2P 句柄
 * @param target_peer_ids 目标节点 Peer ID 数组
 * @param target_count 目标节点数量
 * @param message 消息内容（UTF-8 字符串）
 * @param error_out 错误信息输出
 * @return 错误代码（LOCALP2P_SUCCESS 表示成功）
 */
LocalP2P_ErrorCode localp2p_broadcast_message(LocalP2P_Handle handle,
                                              const char **target_peer_ids,
                                              size_t target_count,
                                              const char *message,
                                              char **error_out);

/* ==========================================================================
 * 内存管理
 * ========================================================================== */

/**
 * @brief 释放错误信息字符串
 *
 * @param error 错误信息字符串
 */
void localp2p_free_error(char *error);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // LOCALP2P_H
