import 'package:flutter/material.dart';
import 'bridge/frb_generated.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 FRB 预热：在应用启动时预先调用一次异步函数
  // 这样首次进入聊天页面时就不需要等待后台线程启动
  try {
    // 预热 FRB：调用一个简单的异步函数来启动后台线程
    RustLib.instance.api.localp2PFfiBridgeP2PIsInitialized();
    print('[FRB Warmup] FRB 后台线程已预热');
  } catch (e) {
    print('[FRB Warmup] 预热失败（忽略）: $e');
  }

  runApp(const App());
}
