/**
 * @file simple.c
 * @brief Local P2P FFI 简单示例程序
 *
 * 演示如何使用 C FFI 接口来发现节点和发送消息
 */

#include "../include/localp2p.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <stdbool.h>
#include <time.h>

/* 全局变量 */
static volatile bool g_running = true;
static LocalP2P_Handle g_handle;

/* 信号处理函数 */
void signal_handler(int sig) {
    (void)sig;
    g_running = false;
    printf("\n正在关闭...\n");
}

/**
 * @brief 事件回调函数
 *
 * @param event 事件数据
 * @param user_data 用户数据（未使用）
 */
void event_callback(LocalP2P_EventData event, void *user_data) {
    (void)user_data;

    switch (event.event_type) {
        case LOCALP2P_EVENT_NODE_DISCOVERED:
            printf("[发现] %s\n", event.peer_id);
            break;

        case LOCALP2P_EVENT_NODE_VERIFIED:
            printf("[验证] %s - %s\n", event.display_name, event.peer_id);
            break;

        case LOCALP2P_EVENT_NODE_OFFLINE:
            printf("[离线] %s\n", event.peer_id);
            break;

        case LOCALP2P_EVENT_MESSAGE_RECEIVED: {
            // 将时间戳转换为可读格式
            time_t timestamp = event.timestamp / 1000;
            struct tm *tm_info = localtime(&timestamp);
            char time_buf[64];
            strftime(time_buf, sizeof(time_buf), "%H:%M:%S", tm_info);

            printf("[消息] %s (%s): %s\n",
                   event.peer_id, time_buf, event.message);
            break;
        }

        case LOCALP2P_EVENT_MESSAGE_SENT:
            printf("[发送] 消息已发送给 %s (ID: %s)\n",
                   event.peer_id, event.message_id);
            break;

        case LOCALP2P_EVENT_PEER_TYPING:
            if (event.is_typing) {
                printf("[输入] %s 正在输入...\n", event.peer_id);
            }
            break;

        default:
            printf("[事件] 类型: %d, Peer: %s\n",
                   event.event_type, event.peer_id);
            break;
    }
}

/**
 * @brief 打印节点列表
 */
void print_nodes(LocalP2P_Handle handle) {
    LocalP2P_NodeInfo *nodes = NULL;
    size_t count = 0;

    LocalP2P_ErrorCode result = localp2p_get_verified_nodes(handle, &nodes, &count);

    if (result == LOCALP2P_SUCCESS && nodes != NULL && count > 0) {
        printf("\n=== 已发现的节点 (%zu) ===\n", count);

        for (size_t i = 0; i < count; i++) {
            LocalP2P_NodeInfo *node = &nodes[i];

            printf("[%zu] %s\n", i + 1, node->display_name);
            printf("    Peer ID: %s\n", node->peer_id);
            printf("    设备名: %s\n", node->device_name);
            printf("    地址数: %zu\n", node->address_count);

            if (i < count - 1) printf("\n");
        }

        printf("=========================\n\n");

        // 释放内存
        localp2p_free_node_list(nodes, count);
    } else {
        printf("\n暂无已发现的节点\n\n");
    }
}

/**
 * @brief 交互式命令行界面
 */
void interactive_loop(LocalP2P_Handle handle) {
    char buffer[1024];
    char local_peer_id[256];
    char device_name[256];

    // 获取本地信息
    if (localp2p_get_local_peer_id(handle, local_peer_id, sizeof(local_peer_id)) == LOCALP2P_SUCCESS) {
        printf("本地 Peer ID: %s\n", local_peer_id);
    }

    if (localp2p_get_device_name(handle, device_name, sizeof(device_name)) == LOCALP2P_SUCCESS) {
        printf("设备名称: %s\n", device_name);
    }

    printf("\n命令:\n");
    printf("  list     - 显示已发现的节点\n");
    printf("  send     - 发送消息\n");
    printf("  help     - 显示帮助\n");
    printf("  quit     - 退出\n\n");

    while (g_running) {
        printf("> ");
        fflush(stdout);

        if (fgets(buffer, sizeof(buffer), stdin) == NULL) {
            break;
        }

        // 移除换行符
        buffer[strcspn(buffer, "\n")] = 0;

        if (strlen(buffer) == 0) {
            continue;
        }

        if (strcmp(buffer, "quit") == 0 || strcmp(buffer, "exit") == 0 || strcmp(buffer, "q") == 0) {
            break;
        } else if (strcmp(buffer, "list") == 0 || strcmp(buffer, "ls") == 0) {
            print_nodes(handle);
        } else if (strcmp(buffer, "send") == 0) {
            printf("输入目标 Peer ID: ");
            if (fgets(buffer, sizeof(buffer), stdin) == NULL) break;

            char target_peer_id[256];
            strncpy(target_peer_id, buffer, sizeof(target_peer_id) - 1);
            target_peer_id[strcspn(target_peer_id, "\n")] = 0;

            printf("输入消息内容: ");
            if (fgets(buffer, sizeof(buffer), stdin) == NULL) break;

            char message[512];
            strncpy(message, buffer, sizeof(message) - 1);
            message[strcspn(message, "\n")] = 0;

            char *error = NULL;
            LocalP2P_ErrorCode result = localp2p_send_message(
                handle,
                target_peer_id,
                message,
                &error
            );

            if (result == LOCALP2P_SUCCESS) {
                printf("✓ 消息已发送\n");
            } else {
                printf("✗ 发送失败: %s\n", error ? error : "未知错误");
                if (error) localp2p_free_error(error);
            }
        } else if (strcmp(buffer, "help") == 0 || strcmp(buffer, "h") == 0) {
            printf("\n命令:\n");
            printf("  list     - 显示已发现的节点\n");
            printf("  send     - 发送消息\n");
            printf("  help     - 显示帮助\n");
            printf("  quit     - 退出\n\n");
        } else {
            printf("未知命令: %s (输入 'help' 查看帮助)\n", buffer);
        }
    }
}

/**
 * @brief 主函数
 */
int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    char *error = NULL;

    printf("========================================\n");
    printf("  Local P2P FFI 示例程序\n");
    printf("========================================\n\n");

    // 设置信号处理
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    // 初始化 P2P 模块
    printf("正在初始化...\n");
    g_handle = localp2p_init("FFI Example Device", &error);

    if (error != NULL) {
        fprintf(stderr, "初始化失败: %s\n", error);
        localp2p_free_error(error);
        return 1;
    }

    printf("✓ 初始化成功\n\n");

    // 启动服务
    printf("正在启动服务...\n");
    LocalP2P_ErrorCode result = localp2p_start(g_handle, event_callback, NULL);

    if (result != LOCALP2P_SUCCESS) {
        fprintf(stderr, "启动失败: 错误代码 %d\n", result);
        localp2p_cleanup(g_handle);
        return 1;
    }

    printf("✓ 服务已启动\n");
    printf("✓ 正在扫描局域网内的节点...\n\n");

    // 交互式循环
    interactive_loop(g_handle);

    // 清理
    printf("\n正在清理资源...\n");
    localp2p_cleanup(g_handle);
    printf("✓ 已清理\n");

    printf("再见！\n");

    return 0;
}
