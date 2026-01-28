// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lib.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$P2PEvent {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String peerId, String addr) nodeDiscovered,
    required TResult Function(String peerId) nodeExpired,
    required TResult Function(String peerId, String displayName) nodeVerified,
    required TResult Function(String peerId) nodeOffline,
    required TResult Function(String peerId, UserInfoJson userInfo)
    userInfoReceived,
    required TResult Function(String from, ChatMessageJson message)
    messageReceived,
    required TResult Function(String to, String messageId) messageSent,
    required TResult Function(String from, bool isTyping) peerTyping,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String peerId, String addr)? nodeDiscovered,
    TResult? Function(String peerId)? nodeExpired,
    TResult? Function(String peerId, String displayName)? nodeVerified,
    TResult? Function(String peerId)? nodeOffline,
    TResult? Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult? Function(String from, ChatMessageJson message)? messageReceived,
    TResult? Function(String to, String messageId)? messageSent,
    TResult? Function(String from, bool isTyping)? peerTyping,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String peerId, String addr)? nodeDiscovered,
    TResult Function(String peerId)? nodeExpired,
    TResult Function(String peerId, String displayName)? nodeVerified,
    TResult Function(String peerId)? nodeOffline,
    TResult Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult Function(String from, ChatMessageJson message)? messageReceived,
    TResult Function(String to, String messageId)? messageSent,
    TResult Function(String from, bool isTyping)? peerTyping,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(P2PEvent_NodeDiscovered value) nodeDiscovered,
    required TResult Function(P2PEvent_NodeExpired value) nodeExpired,
    required TResult Function(P2PEvent_NodeVerified value) nodeVerified,
    required TResult Function(P2PEvent_NodeOffline value) nodeOffline,
    required TResult Function(P2PEvent_UserInfoReceived value) userInfoReceived,
    required TResult Function(P2PEvent_MessageReceived value) messageReceived,
    required TResult Function(P2PEvent_MessageSent value) messageSent,
    required TResult Function(P2PEvent_PeerTyping value) peerTyping,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult? Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult? Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult? Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult? Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult? Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult? Function(P2PEvent_MessageSent value)? messageSent,
    TResult? Function(P2PEvent_PeerTyping value)? peerTyping,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult Function(P2PEvent_MessageSent value)? messageSent,
    TResult Function(P2PEvent_PeerTyping value)? peerTyping,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $P2PEventCopyWith<$Res> {
  factory $P2PEventCopyWith(P2PEvent value, $Res Function(P2PEvent) then) =
      _$P2PEventCopyWithImpl<$Res, P2PEvent>;
}

/// @nodoc
class _$P2PEventCopyWithImpl<$Res, $Val extends P2PEvent>
    implements $P2PEventCopyWith<$Res> {
  _$P2PEventCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$P2PEvent_NodeDiscoveredImplCopyWith<$Res> {
  factory _$$P2PEvent_NodeDiscoveredImplCopyWith(
    _$P2PEvent_NodeDiscoveredImpl value,
    $Res Function(_$P2PEvent_NodeDiscoveredImpl) then,
  ) = __$$P2PEvent_NodeDiscoveredImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String peerId, String addr});
}

/// @nodoc
class __$$P2PEvent_NodeDiscoveredImplCopyWithImpl<$Res>
    extends _$P2PEventCopyWithImpl<$Res, _$P2PEvent_NodeDiscoveredImpl>
    implements _$$P2PEvent_NodeDiscoveredImplCopyWith<$Res> {
  __$$P2PEvent_NodeDiscoveredImplCopyWithImpl(
    _$P2PEvent_NodeDiscoveredImpl _value,
    $Res Function(_$P2PEvent_NodeDiscoveredImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? peerId = null, Object? addr = null}) {
    return _then(
      _$P2PEvent_NodeDiscoveredImpl(
        peerId: null == peerId
            ? _value.peerId
            : peerId // ignore: cast_nullable_to_non_nullable
                  as String,
        addr: null == addr
            ? _value.addr
            : addr // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$P2PEvent_NodeDiscoveredImpl extends P2PEvent_NodeDiscovered {
  const _$P2PEvent_NodeDiscoveredImpl({
    required this.peerId,
    required this.addr,
  }) : super._();

  @override
  final String peerId;
  @override
  final String addr;

  @override
  String toString() {
    return 'P2PEvent.nodeDiscovered(peerId: $peerId, addr: $addr)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$P2PEvent_NodeDiscoveredImpl &&
            (identical(other.peerId, peerId) || other.peerId == peerId) &&
            (identical(other.addr, addr) || other.addr == addr));
  }

  @override
  int get hashCode => Object.hash(runtimeType, peerId, addr);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$P2PEvent_NodeDiscoveredImplCopyWith<_$P2PEvent_NodeDiscoveredImpl>
  get copyWith =>
      __$$P2PEvent_NodeDiscoveredImplCopyWithImpl<
        _$P2PEvent_NodeDiscoveredImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String peerId, String addr) nodeDiscovered,
    required TResult Function(String peerId) nodeExpired,
    required TResult Function(String peerId, String displayName) nodeVerified,
    required TResult Function(String peerId) nodeOffline,
    required TResult Function(String peerId, UserInfoJson userInfo)
    userInfoReceived,
    required TResult Function(String from, ChatMessageJson message)
    messageReceived,
    required TResult Function(String to, String messageId) messageSent,
    required TResult Function(String from, bool isTyping) peerTyping,
  }) {
    return nodeDiscovered(peerId, addr);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String peerId, String addr)? nodeDiscovered,
    TResult? Function(String peerId)? nodeExpired,
    TResult? Function(String peerId, String displayName)? nodeVerified,
    TResult? Function(String peerId)? nodeOffline,
    TResult? Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult? Function(String from, ChatMessageJson message)? messageReceived,
    TResult? Function(String to, String messageId)? messageSent,
    TResult? Function(String from, bool isTyping)? peerTyping,
  }) {
    return nodeDiscovered?.call(peerId, addr);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String peerId, String addr)? nodeDiscovered,
    TResult Function(String peerId)? nodeExpired,
    TResult Function(String peerId, String displayName)? nodeVerified,
    TResult Function(String peerId)? nodeOffline,
    TResult Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult Function(String from, ChatMessageJson message)? messageReceived,
    TResult Function(String to, String messageId)? messageSent,
    TResult Function(String from, bool isTyping)? peerTyping,
    required TResult orElse(),
  }) {
    if (nodeDiscovered != null) {
      return nodeDiscovered(peerId, addr);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(P2PEvent_NodeDiscovered value) nodeDiscovered,
    required TResult Function(P2PEvent_NodeExpired value) nodeExpired,
    required TResult Function(P2PEvent_NodeVerified value) nodeVerified,
    required TResult Function(P2PEvent_NodeOffline value) nodeOffline,
    required TResult Function(P2PEvent_UserInfoReceived value) userInfoReceived,
    required TResult Function(P2PEvent_MessageReceived value) messageReceived,
    required TResult Function(P2PEvent_MessageSent value) messageSent,
    required TResult Function(P2PEvent_PeerTyping value) peerTyping,
  }) {
    return nodeDiscovered(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult? Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult? Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult? Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult? Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult? Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult? Function(P2PEvent_MessageSent value)? messageSent,
    TResult? Function(P2PEvent_PeerTyping value)? peerTyping,
  }) {
    return nodeDiscovered?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult Function(P2PEvent_MessageSent value)? messageSent,
    TResult Function(P2PEvent_PeerTyping value)? peerTyping,
    required TResult orElse(),
  }) {
    if (nodeDiscovered != null) {
      return nodeDiscovered(this);
    }
    return orElse();
  }
}

abstract class P2PEvent_NodeDiscovered extends P2PEvent {
  const factory P2PEvent_NodeDiscovered({
    required final String peerId,
    required final String addr,
  }) = _$P2PEvent_NodeDiscoveredImpl;
  const P2PEvent_NodeDiscovered._() : super._();

  String get peerId;
  String get addr;

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$P2PEvent_NodeDiscoveredImplCopyWith<_$P2PEvent_NodeDiscoveredImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$P2PEvent_NodeExpiredImplCopyWith<$Res> {
  factory _$$P2PEvent_NodeExpiredImplCopyWith(
    _$P2PEvent_NodeExpiredImpl value,
    $Res Function(_$P2PEvent_NodeExpiredImpl) then,
  ) = __$$P2PEvent_NodeExpiredImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String peerId});
}

/// @nodoc
class __$$P2PEvent_NodeExpiredImplCopyWithImpl<$Res>
    extends _$P2PEventCopyWithImpl<$Res, _$P2PEvent_NodeExpiredImpl>
    implements _$$P2PEvent_NodeExpiredImplCopyWith<$Res> {
  __$$P2PEvent_NodeExpiredImplCopyWithImpl(
    _$P2PEvent_NodeExpiredImpl _value,
    $Res Function(_$P2PEvent_NodeExpiredImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? peerId = null}) {
    return _then(
      _$P2PEvent_NodeExpiredImpl(
        peerId: null == peerId
            ? _value.peerId
            : peerId // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$P2PEvent_NodeExpiredImpl extends P2PEvent_NodeExpired {
  const _$P2PEvent_NodeExpiredImpl({required this.peerId}) : super._();

  @override
  final String peerId;

  @override
  String toString() {
    return 'P2PEvent.nodeExpired(peerId: $peerId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$P2PEvent_NodeExpiredImpl &&
            (identical(other.peerId, peerId) || other.peerId == peerId));
  }

  @override
  int get hashCode => Object.hash(runtimeType, peerId);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$P2PEvent_NodeExpiredImplCopyWith<_$P2PEvent_NodeExpiredImpl>
  get copyWith =>
      __$$P2PEvent_NodeExpiredImplCopyWithImpl<_$P2PEvent_NodeExpiredImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String peerId, String addr) nodeDiscovered,
    required TResult Function(String peerId) nodeExpired,
    required TResult Function(String peerId, String displayName) nodeVerified,
    required TResult Function(String peerId) nodeOffline,
    required TResult Function(String peerId, UserInfoJson userInfo)
    userInfoReceived,
    required TResult Function(String from, ChatMessageJson message)
    messageReceived,
    required TResult Function(String to, String messageId) messageSent,
    required TResult Function(String from, bool isTyping) peerTyping,
  }) {
    return nodeExpired(peerId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String peerId, String addr)? nodeDiscovered,
    TResult? Function(String peerId)? nodeExpired,
    TResult? Function(String peerId, String displayName)? nodeVerified,
    TResult? Function(String peerId)? nodeOffline,
    TResult? Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult? Function(String from, ChatMessageJson message)? messageReceived,
    TResult? Function(String to, String messageId)? messageSent,
    TResult? Function(String from, bool isTyping)? peerTyping,
  }) {
    return nodeExpired?.call(peerId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String peerId, String addr)? nodeDiscovered,
    TResult Function(String peerId)? nodeExpired,
    TResult Function(String peerId, String displayName)? nodeVerified,
    TResult Function(String peerId)? nodeOffline,
    TResult Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult Function(String from, ChatMessageJson message)? messageReceived,
    TResult Function(String to, String messageId)? messageSent,
    TResult Function(String from, bool isTyping)? peerTyping,
    required TResult orElse(),
  }) {
    if (nodeExpired != null) {
      return nodeExpired(peerId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(P2PEvent_NodeDiscovered value) nodeDiscovered,
    required TResult Function(P2PEvent_NodeExpired value) nodeExpired,
    required TResult Function(P2PEvent_NodeVerified value) nodeVerified,
    required TResult Function(P2PEvent_NodeOffline value) nodeOffline,
    required TResult Function(P2PEvent_UserInfoReceived value) userInfoReceived,
    required TResult Function(P2PEvent_MessageReceived value) messageReceived,
    required TResult Function(P2PEvent_MessageSent value) messageSent,
    required TResult Function(P2PEvent_PeerTyping value) peerTyping,
  }) {
    return nodeExpired(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult? Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult? Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult? Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult? Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult? Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult? Function(P2PEvent_MessageSent value)? messageSent,
    TResult? Function(P2PEvent_PeerTyping value)? peerTyping,
  }) {
    return nodeExpired?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult Function(P2PEvent_MessageSent value)? messageSent,
    TResult Function(P2PEvent_PeerTyping value)? peerTyping,
    required TResult orElse(),
  }) {
    if (nodeExpired != null) {
      return nodeExpired(this);
    }
    return orElse();
  }
}

abstract class P2PEvent_NodeExpired extends P2PEvent {
  const factory P2PEvent_NodeExpired({required final String peerId}) =
      _$P2PEvent_NodeExpiredImpl;
  const P2PEvent_NodeExpired._() : super._();

  String get peerId;

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$P2PEvent_NodeExpiredImplCopyWith<_$P2PEvent_NodeExpiredImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$P2PEvent_NodeVerifiedImplCopyWith<$Res> {
  factory _$$P2PEvent_NodeVerifiedImplCopyWith(
    _$P2PEvent_NodeVerifiedImpl value,
    $Res Function(_$P2PEvent_NodeVerifiedImpl) then,
  ) = __$$P2PEvent_NodeVerifiedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String peerId, String displayName});
}

/// @nodoc
class __$$P2PEvent_NodeVerifiedImplCopyWithImpl<$Res>
    extends _$P2PEventCopyWithImpl<$Res, _$P2PEvent_NodeVerifiedImpl>
    implements _$$P2PEvent_NodeVerifiedImplCopyWith<$Res> {
  __$$P2PEvent_NodeVerifiedImplCopyWithImpl(
    _$P2PEvent_NodeVerifiedImpl _value,
    $Res Function(_$P2PEvent_NodeVerifiedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? peerId = null, Object? displayName = null}) {
    return _then(
      _$P2PEvent_NodeVerifiedImpl(
        peerId: null == peerId
            ? _value.peerId
            : peerId // ignore: cast_nullable_to_non_nullable
                  as String,
        displayName: null == displayName
            ? _value.displayName
            : displayName // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$P2PEvent_NodeVerifiedImpl extends P2PEvent_NodeVerified {
  const _$P2PEvent_NodeVerifiedImpl({
    required this.peerId,
    required this.displayName,
  }) : super._();

  @override
  final String peerId;
  @override
  final String displayName;

  @override
  String toString() {
    return 'P2PEvent.nodeVerified(peerId: $peerId, displayName: $displayName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$P2PEvent_NodeVerifiedImpl &&
            (identical(other.peerId, peerId) || other.peerId == peerId) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName));
  }

  @override
  int get hashCode => Object.hash(runtimeType, peerId, displayName);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$P2PEvent_NodeVerifiedImplCopyWith<_$P2PEvent_NodeVerifiedImpl>
  get copyWith =>
      __$$P2PEvent_NodeVerifiedImplCopyWithImpl<_$P2PEvent_NodeVerifiedImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String peerId, String addr) nodeDiscovered,
    required TResult Function(String peerId) nodeExpired,
    required TResult Function(String peerId, String displayName) nodeVerified,
    required TResult Function(String peerId) nodeOffline,
    required TResult Function(String peerId, UserInfoJson userInfo)
    userInfoReceived,
    required TResult Function(String from, ChatMessageJson message)
    messageReceived,
    required TResult Function(String to, String messageId) messageSent,
    required TResult Function(String from, bool isTyping) peerTyping,
  }) {
    return nodeVerified(peerId, displayName);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String peerId, String addr)? nodeDiscovered,
    TResult? Function(String peerId)? nodeExpired,
    TResult? Function(String peerId, String displayName)? nodeVerified,
    TResult? Function(String peerId)? nodeOffline,
    TResult? Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult? Function(String from, ChatMessageJson message)? messageReceived,
    TResult? Function(String to, String messageId)? messageSent,
    TResult? Function(String from, bool isTyping)? peerTyping,
  }) {
    return nodeVerified?.call(peerId, displayName);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String peerId, String addr)? nodeDiscovered,
    TResult Function(String peerId)? nodeExpired,
    TResult Function(String peerId, String displayName)? nodeVerified,
    TResult Function(String peerId)? nodeOffline,
    TResult Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult Function(String from, ChatMessageJson message)? messageReceived,
    TResult Function(String to, String messageId)? messageSent,
    TResult Function(String from, bool isTyping)? peerTyping,
    required TResult orElse(),
  }) {
    if (nodeVerified != null) {
      return nodeVerified(peerId, displayName);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(P2PEvent_NodeDiscovered value) nodeDiscovered,
    required TResult Function(P2PEvent_NodeExpired value) nodeExpired,
    required TResult Function(P2PEvent_NodeVerified value) nodeVerified,
    required TResult Function(P2PEvent_NodeOffline value) nodeOffline,
    required TResult Function(P2PEvent_UserInfoReceived value) userInfoReceived,
    required TResult Function(P2PEvent_MessageReceived value) messageReceived,
    required TResult Function(P2PEvent_MessageSent value) messageSent,
    required TResult Function(P2PEvent_PeerTyping value) peerTyping,
  }) {
    return nodeVerified(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult? Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult? Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult? Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult? Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult? Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult? Function(P2PEvent_MessageSent value)? messageSent,
    TResult? Function(P2PEvent_PeerTyping value)? peerTyping,
  }) {
    return nodeVerified?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult Function(P2PEvent_MessageSent value)? messageSent,
    TResult Function(P2PEvent_PeerTyping value)? peerTyping,
    required TResult orElse(),
  }) {
    if (nodeVerified != null) {
      return nodeVerified(this);
    }
    return orElse();
  }
}

abstract class P2PEvent_NodeVerified extends P2PEvent {
  const factory P2PEvent_NodeVerified({
    required final String peerId,
    required final String displayName,
  }) = _$P2PEvent_NodeVerifiedImpl;
  const P2PEvent_NodeVerified._() : super._();

  String get peerId;
  String get displayName;

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$P2PEvent_NodeVerifiedImplCopyWith<_$P2PEvent_NodeVerifiedImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$P2PEvent_NodeOfflineImplCopyWith<$Res> {
  factory _$$P2PEvent_NodeOfflineImplCopyWith(
    _$P2PEvent_NodeOfflineImpl value,
    $Res Function(_$P2PEvent_NodeOfflineImpl) then,
  ) = __$$P2PEvent_NodeOfflineImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String peerId});
}

/// @nodoc
class __$$P2PEvent_NodeOfflineImplCopyWithImpl<$Res>
    extends _$P2PEventCopyWithImpl<$Res, _$P2PEvent_NodeOfflineImpl>
    implements _$$P2PEvent_NodeOfflineImplCopyWith<$Res> {
  __$$P2PEvent_NodeOfflineImplCopyWithImpl(
    _$P2PEvent_NodeOfflineImpl _value,
    $Res Function(_$P2PEvent_NodeOfflineImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? peerId = null}) {
    return _then(
      _$P2PEvent_NodeOfflineImpl(
        peerId: null == peerId
            ? _value.peerId
            : peerId // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$P2PEvent_NodeOfflineImpl extends P2PEvent_NodeOffline {
  const _$P2PEvent_NodeOfflineImpl({required this.peerId}) : super._();

  @override
  final String peerId;

  @override
  String toString() {
    return 'P2PEvent.nodeOffline(peerId: $peerId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$P2PEvent_NodeOfflineImpl &&
            (identical(other.peerId, peerId) || other.peerId == peerId));
  }

  @override
  int get hashCode => Object.hash(runtimeType, peerId);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$P2PEvent_NodeOfflineImplCopyWith<_$P2PEvent_NodeOfflineImpl>
  get copyWith =>
      __$$P2PEvent_NodeOfflineImplCopyWithImpl<_$P2PEvent_NodeOfflineImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String peerId, String addr) nodeDiscovered,
    required TResult Function(String peerId) nodeExpired,
    required TResult Function(String peerId, String displayName) nodeVerified,
    required TResult Function(String peerId) nodeOffline,
    required TResult Function(String peerId, UserInfoJson userInfo)
    userInfoReceived,
    required TResult Function(String from, ChatMessageJson message)
    messageReceived,
    required TResult Function(String to, String messageId) messageSent,
    required TResult Function(String from, bool isTyping) peerTyping,
  }) {
    return nodeOffline(peerId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String peerId, String addr)? nodeDiscovered,
    TResult? Function(String peerId)? nodeExpired,
    TResult? Function(String peerId, String displayName)? nodeVerified,
    TResult? Function(String peerId)? nodeOffline,
    TResult? Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult? Function(String from, ChatMessageJson message)? messageReceived,
    TResult? Function(String to, String messageId)? messageSent,
    TResult? Function(String from, bool isTyping)? peerTyping,
  }) {
    return nodeOffline?.call(peerId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String peerId, String addr)? nodeDiscovered,
    TResult Function(String peerId)? nodeExpired,
    TResult Function(String peerId, String displayName)? nodeVerified,
    TResult Function(String peerId)? nodeOffline,
    TResult Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult Function(String from, ChatMessageJson message)? messageReceived,
    TResult Function(String to, String messageId)? messageSent,
    TResult Function(String from, bool isTyping)? peerTyping,
    required TResult orElse(),
  }) {
    if (nodeOffline != null) {
      return nodeOffline(peerId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(P2PEvent_NodeDiscovered value) nodeDiscovered,
    required TResult Function(P2PEvent_NodeExpired value) nodeExpired,
    required TResult Function(P2PEvent_NodeVerified value) nodeVerified,
    required TResult Function(P2PEvent_NodeOffline value) nodeOffline,
    required TResult Function(P2PEvent_UserInfoReceived value) userInfoReceived,
    required TResult Function(P2PEvent_MessageReceived value) messageReceived,
    required TResult Function(P2PEvent_MessageSent value) messageSent,
    required TResult Function(P2PEvent_PeerTyping value) peerTyping,
  }) {
    return nodeOffline(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult? Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult? Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult? Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult? Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult? Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult? Function(P2PEvent_MessageSent value)? messageSent,
    TResult? Function(P2PEvent_PeerTyping value)? peerTyping,
  }) {
    return nodeOffline?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult Function(P2PEvent_MessageSent value)? messageSent,
    TResult Function(P2PEvent_PeerTyping value)? peerTyping,
    required TResult orElse(),
  }) {
    if (nodeOffline != null) {
      return nodeOffline(this);
    }
    return orElse();
  }
}

abstract class P2PEvent_NodeOffline extends P2PEvent {
  const factory P2PEvent_NodeOffline({required final String peerId}) =
      _$P2PEvent_NodeOfflineImpl;
  const P2PEvent_NodeOffline._() : super._();

  String get peerId;

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$P2PEvent_NodeOfflineImplCopyWith<_$P2PEvent_NodeOfflineImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$P2PEvent_UserInfoReceivedImplCopyWith<$Res> {
  factory _$$P2PEvent_UserInfoReceivedImplCopyWith(
    _$P2PEvent_UserInfoReceivedImpl value,
    $Res Function(_$P2PEvent_UserInfoReceivedImpl) then,
  ) = __$$P2PEvent_UserInfoReceivedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String peerId, UserInfoJson userInfo});
}

/// @nodoc
class __$$P2PEvent_UserInfoReceivedImplCopyWithImpl<$Res>
    extends _$P2PEventCopyWithImpl<$Res, _$P2PEvent_UserInfoReceivedImpl>
    implements _$$P2PEvent_UserInfoReceivedImplCopyWith<$Res> {
  __$$P2PEvent_UserInfoReceivedImplCopyWithImpl(
    _$P2PEvent_UserInfoReceivedImpl _value,
    $Res Function(_$P2PEvent_UserInfoReceivedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? peerId = null, Object? userInfo = null}) {
    return _then(
      _$P2PEvent_UserInfoReceivedImpl(
        peerId: null == peerId
            ? _value.peerId
            : peerId // ignore: cast_nullable_to_non_nullable
                  as String,
        userInfo: null == userInfo
            ? _value.userInfo
            : userInfo // ignore: cast_nullable_to_non_nullable
                  as UserInfoJson,
      ),
    );
  }
}

/// @nodoc

class _$P2PEvent_UserInfoReceivedImpl extends P2PEvent_UserInfoReceived {
  const _$P2PEvent_UserInfoReceivedImpl({
    required this.peerId,
    required this.userInfo,
  }) : super._();

  @override
  final String peerId;
  @override
  final UserInfoJson userInfo;

  @override
  String toString() {
    return 'P2PEvent.userInfoReceived(peerId: $peerId, userInfo: $userInfo)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$P2PEvent_UserInfoReceivedImpl &&
            (identical(other.peerId, peerId) || other.peerId == peerId) &&
            (identical(other.userInfo, userInfo) ||
                other.userInfo == userInfo));
  }

  @override
  int get hashCode => Object.hash(runtimeType, peerId, userInfo);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$P2PEvent_UserInfoReceivedImplCopyWith<_$P2PEvent_UserInfoReceivedImpl>
  get copyWith =>
      __$$P2PEvent_UserInfoReceivedImplCopyWithImpl<
        _$P2PEvent_UserInfoReceivedImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String peerId, String addr) nodeDiscovered,
    required TResult Function(String peerId) nodeExpired,
    required TResult Function(String peerId, String displayName) nodeVerified,
    required TResult Function(String peerId) nodeOffline,
    required TResult Function(String peerId, UserInfoJson userInfo)
    userInfoReceived,
    required TResult Function(String from, ChatMessageJson message)
    messageReceived,
    required TResult Function(String to, String messageId) messageSent,
    required TResult Function(String from, bool isTyping) peerTyping,
  }) {
    return userInfoReceived(peerId, userInfo);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String peerId, String addr)? nodeDiscovered,
    TResult? Function(String peerId)? nodeExpired,
    TResult? Function(String peerId, String displayName)? nodeVerified,
    TResult? Function(String peerId)? nodeOffline,
    TResult? Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult? Function(String from, ChatMessageJson message)? messageReceived,
    TResult? Function(String to, String messageId)? messageSent,
    TResult? Function(String from, bool isTyping)? peerTyping,
  }) {
    return userInfoReceived?.call(peerId, userInfo);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String peerId, String addr)? nodeDiscovered,
    TResult Function(String peerId)? nodeExpired,
    TResult Function(String peerId, String displayName)? nodeVerified,
    TResult Function(String peerId)? nodeOffline,
    TResult Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult Function(String from, ChatMessageJson message)? messageReceived,
    TResult Function(String to, String messageId)? messageSent,
    TResult Function(String from, bool isTyping)? peerTyping,
    required TResult orElse(),
  }) {
    if (userInfoReceived != null) {
      return userInfoReceived(peerId, userInfo);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(P2PEvent_NodeDiscovered value) nodeDiscovered,
    required TResult Function(P2PEvent_NodeExpired value) nodeExpired,
    required TResult Function(P2PEvent_NodeVerified value) nodeVerified,
    required TResult Function(P2PEvent_NodeOffline value) nodeOffline,
    required TResult Function(P2PEvent_UserInfoReceived value) userInfoReceived,
    required TResult Function(P2PEvent_MessageReceived value) messageReceived,
    required TResult Function(P2PEvent_MessageSent value) messageSent,
    required TResult Function(P2PEvent_PeerTyping value) peerTyping,
  }) {
    return userInfoReceived(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult? Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult? Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult? Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult? Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult? Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult? Function(P2PEvent_MessageSent value)? messageSent,
    TResult? Function(P2PEvent_PeerTyping value)? peerTyping,
  }) {
    return userInfoReceived?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult Function(P2PEvent_MessageSent value)? messageSent,
    TResult Function(P2PEvent_PeerTyping value)? peerTyping,
    required TResult orElse(),
  }) {
    if (userInfoReceived != null) {
      return userInfoReceived(this);
    }
    return orElse();
  }
}

abstract class P2PEvent_UserInfoReceived extends P2PEvent {
  const factory P2PEvent_UserInfoReceived({
    required final String peerId,
    required final UserInfoJson userInfo,
  }) = _$P2PEvent_UserInfoReceivedImpl;
  const P2PEvent_UserInfoReceived._() : super._();

  String get peerId;
  UserInfoJson get userInfo;

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$P2PEvent_UserInfoReceivedImplCopyWith<_$P2PEvent_UserInfoReceivedImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$P2PEvent_MessageReceivedImplCopyWith<$Res> {
  factory _$$P2PEvent_MessageReceivedImplCopyWith(
    _$P2PEvent_MessageReceivedImpl value,
    $Res Function(_$P2PEvent_MessageReceivedImpl) then,
  ) = __$$P2PEvent_MessageReceivedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String from, ChatMessageJson message});
}

/// @nodoc
class __$$P2PEvent_MessageReceivedImplCopyWithImpl<$Res>
    extends _$P2PEventCopyWithImpl<$Res, _$P2PEvent_MessageReceivedImpl>
    implements _$$P2PEvent_MessageReceivedImplCopyWith<$Res> {
  __$$P2PEvent_MessageReceivedImplCopyWithImpl(
    _$P2PEvent_MessageReceivedImpl _value,
    $Res Function(_$P2PEvent_MessageReceivedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? from = null, Object? message = null}) {
    return _then(
      _$P2PEvent_MessageReceivedImpl(
        from: null == from
            ? _value.from
            : from // ignore: cast_nullable_to_non_nullable
                  as String,
        message: null == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as ChatMessageJson,
      ),
    );
  }
}

/// @nodoc

class _$P2PEvent_MessageReceivedImpl extends P2PEvent_MessageReceived {
  const _$P2PEvent_MessageReceivedImpl({
    required this.from,
    required this.message,
  }) : super._();

  @override
  final String from;
  @override
  final ChatMessageJson message;

  @override
  String toString() {
    return 'P2PEvent.messageReceived(from: $from, message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$P2PEvent_MessageReceivedImpl &&
            (identical(other.from, from) || other.from == from) &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, from, message);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$P2PEvent_MessageReceivedImplCopyWith<_$P2PEvent_MessageReceivedImpl>
  get copyWith =>
      __$$P2PEvent_MessageReceivedImplCopyWithImpl<
        _$P2PEvent_MessageReceivedImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String peerId, String addr) nodeDiscovered,
    required TResult Function(String peerId) nodeExpired,
    required TResult Function(String peerId, String displayName) nodeVerified,
    required TResult Function(String peerId) nodeOffline,
    required TResult Function(String peerId, UserInfoJson userInfo)
    userInfoReceived,
    required TResult Function(String from, ChatMessageJson message)
    messageReceived,
    required TResult Function(String to, String messageId) messageSent,
    required TResult Function(String from, bool isTyping) peerTyping,
  }) {
    return messageReceived(from, message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String peerId, String addr)? nodeDiscovered,
    TResult? Function(String peerId)? nodeExpired,
    TResult? Function(String peerId, String displayName)? nodeVerified,
    TResult? Function(String peerId)? nodeOffline,
    TResult? Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult? Function(String from, ChatMessageJson message)? messageReceived,
    TResult? Function(String to, String messageId)? messageSent,
    TResult? Function(String from, bool isTyping)? peerTyping,
  }) {
    return messageReceived?.call(from, message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String peerId, String addr)? nodeDiscovered,
    TResult Function(String peerId)? nodeExpired,
    TResult Function(String peerId, String displayName)? nodeVerified,
    TResult Function(String peerId)? nodeOffline,
    TResult Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult Function(String from, ChatMessageJson message)? messageReceived,
    TResult Function(String to, String messageId)? messageSent,
    TResult Function(String from, bool isTyping)? peerTyping,
    required TResult orElse(),
  }) {
    if (messageReceived != null) {
      return messageReceived(from, message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(P2PEvent_NodeDiscovered value) nodeDiscovered,
    required TResult Function(P2PEvent_NodeExpired value) nodeExpired,
    required TResult Function(P2PEvent_NodeVerified value) nodeVerified,
    required TResult Function(P2PEvent_NodeOffline value) nodeOffline,
    required TResult Function(P2PEvent_UserInfoReceived value) userInfoReceived,
    required TResult Function(P2PEvent_MessageReceived value) messageReceived,
    required TResult Function(P2PEvent_MessageSent value) messageSent,
    required TResult Function(P2PEvent_PeerTyping value) peerTyping,
  }) {
    return messageReceived(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult? Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult? Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult? Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult? Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult? Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult? Function(P2PEvent_MessageSent value)? messageSent,
    TResult? Function(P2PEvent_PeerTyping value)? peerTyping,
  }) {
    return messageReceived?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult Function(P2PEvent_MessageSent value)? messageSent,
    TResult Function(P2PEvent_PeerTyping value)? peerTyping,
    required TResult orElse(),
  }) {
    if (messageReceived != null) {
      return messageReceived(this);
    }
    return orElse();
  }
}

abstract class P2PEvent_MessageReceived extends P2PEvent {
  const factory P2PEvent_MessageReceived({
    required final String from,
    required final ChatMessageJson message,
  }) = _$P2PEvent_MessageReceivedImpl;
  const P2PEvent_MessageReceived._() : super._();

  String get from;
  ChatMessageJson get message;

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$P2PEvent_MessageReceivedImplCopyWith<_$P2PEvent_MessageReceivedImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$P2PEvent_MessageSentImplCopyWith<$Res> {
  factory _$$P2PEvent_MessageSentImplCopyWith(
    _$P2PEvent_MessageSentImpl value,
    $Res Function(_$P2PEvent_MessageSentImpl) then,
  ) = __$$P2PEvent_MessageSentImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String to, String messageId});
}

/// @nodoc
class __$$P2PEvent_MessageSentImplCopyWithImpl<$Res>
    extends _$P2PEventCopyWithImpl<$Res, _$P2PEvent_MessageSentImpl>
    implements _$$P2PEvent_MessageSentImplCopyWith<$Res> {
  __$$P2PEvent_MessageSentImplCopyWithImpl(
    _$P2PEvent_MessageSentImpl _value,
    $Res Function(_$P2PEvent_MessageSentImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? to = null, Object? messageId = null}) {
    return _then(
      _$P2PEvent_MessageSentImpl(
        to: null == to
            ? _value.to
            : to // ignore: cast_nullable_to_non_nullable
                  as String,
        messageId: null == messageId
            ? _value.messageId
            : messageId // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$P2PEvent_MessageSentImpl extends P2PEvent_MessageSent {
  const _$P2PEvent_MessageSentImpl({required this.to, required this.messageId})
    : super._();

  @override
  final String to;
  @override
  final String messageId;

  @override
  String toString() {
    return 'P2PEvent.messageSent(to: $to, messageId: $messageId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$P2PEvent_MessageSentImpl &&
            (identical(other.to, to) || other.to == to) &&
            (identical(other.messageId, messageId) ||
                other.messageId == messageId));
  }

  @override
  int get hashCode => Object.hash(runtimeType, to, messageId);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$P2PEvent_MessageSentImplCopyWith<_$P2PEvent_MessageSentImpl>
  get copyWith =>
      __$$P2PEvent_MessageSentImplCopyWithImpl<_$P2PEvent_MessageSentImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String peerId, String addr) nodeDiscovered,
    required TResult Function(String peerId) nodeExpired,
    required TResult Function(String peerId, String displayName) nodeVerified,
    required TResult Function(String peerId) nodeOffline,
    required TResult Function(String peerId, UserInfoJson userInfo)
    userInfoReceived,
    required TResult Function(String from, ChatMessageJson message)
    messageReceived,
    required TResult Function(String to, String messageId) messageSent,
    required TResult Function(String from, bool isTyping) peerTyping,
  }) {
    return messageSent(to, messageId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String peerId, String addr)? nodeDiscovered,
    TResult? Function(String peerId)? nodeExpired,
    TResult? Function(String peerId, String displayName)? nodeVerified,
    TResult? Function(String peerId)? nodeOffline,
    TResult? Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult? Function(String from, ChatMessageJson message)? messageReceived,
    TResult? Function(String to, String messageId)? messageSent,
    TResult? Function(String from, bool isTyping)? peerTyping,
  }) {
    return messageSent?.call(to, messageId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String peerId, String addr)? nodeDiscovered,
    TResult Function(String peerId)? nodeExpired,
    TResult Function(String peerId, String displayName)? nodeVerified,
    TResult Function(String peerId)? nodeOffline,
    TResult Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult Function(String from, ChatMessageJson message)? messageReceived,
    TResult Function(String to, String messageId)? messageSent,
    TResult Function(String from, bool isTyping)? peerTyping,
    required TResult orElse(),
  }) {
    if (messageSent != null) {
      return messageSent(to, messageId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(P2PEvent_NodeDiscovered value) nodeDiscovered,
    required TResult Function(P2PEvent_NodeExpired value) nodeExpired,
    required TResult Function(P2PEvent_NodeVerified value) nodeVerified,
    required TResult Function(P2PEvent_NodeOffline value) nodeOffline,
    required TResult Function(P2PEvent_UserInfoReceived value) userInfoReceived,
    required TResult Function(P2PEvent_MessageReceived value) messageReceived,
    required TResult Function(P2PEvent_MessageSent value) messageSent,
    required TResult Function(P2PEvent_PeerTyping value) peerTyping,
  }) {
    return messageSent(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult? Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult? Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult? Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult? Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult? Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult? Function(P2PEvent_MessageSent value)? messageSent,
    TResult? Function(P2PEvent_PeerTyping value)? peerTyping,
  }) {
    return messageSent?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult Function(P2PEvent_MessageSent value)? messageSent,
    TResult Function(P2PEvent_PeerTyping value)? peerTyping,
    required TResult orElse(),
  }) {
    if (messageSent != null) {
      return messageSent(this);
    }
    return orElse();
  }
}

abstract class P2PEvent_MessageSent extends P2PEvent {
  const factory P2PEvent_MessageSent({
    required final String to,
    required final String messageId,
  }) = _$P2PEvent_MessageSentImpl;
  const P2PEvent_MessageSent._() : super._();

  String get to;
  String get messageId;

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$P2PEvent_MessageSentImplCopyWith<_$P2PEvent_MessageSentImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$P2PEvent_PeerTypingImplCopyWith<$Res> {
  factory _$$P2PEvent_PeerTypingImplCopyWith(
    _$P2PEvent_PeerTypingImpl value,
    $Res Function(_$P2PEvent_PeerTypingImpl) then,
  ) = __$$P2PEvent_PeerTypingImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String from, bool isTyping});
}

/// @nodoc
class __$$P2PEvent_PeerTypingImplCopyWithImpl<$Res>
    extends _$P2PEventCopyWithImpl<$Res, _$P2PEvent_PeerTypingImpl>
    implements _$$P2PEvent_PeerTypingImplCopyWith<$Res> {
  __$$P2PEvent_PeerTypingImplCopyWithImpl(
    _$P2PEvent_PeerTypingImpl _value,
    $Res Function(_$P2PEvent_PeerTypingImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? from = null, Object? isTyping = null}) {
    return _then(
      _$P2PEvent_PeerTypingImpl(
        from: null == from
            ? _value.from
            : from // ignore: cast_nullable_to_non_nullable
                  as String,
        isTyping: null == isTyping
            ? _value.isTyping
            : isTyping // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc

class _$P2PEvent_PeerTypingImpl extends P2PEvent_PeerTyping {
  const _$P2PEvent_PeerTypingImpl({required this.from, required this.isTyping})
    : super._();

  @override
  final String from;
  @override
  final bool isTyping;

  @override
  String toString() {
    return 'P2PEvent.peerTyping(from: $from, isTyping: $isTyping)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$P2PEvent_PeerTypingImpl &&
            (identical(other.from, from) || other.from == from) &&
            (identical(other.isTyping, isTyping) ||
                other.isTyping == isTyping));
  }

  @override
  int get hashCode => Object.hash(runtimeType, from, isTyping);

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$P2PEvent_PeerTypingImplCopyWith<_$P2PEvent_PeerTypingImpl> get copyWith =>
      __$$P2PEvent_PeerTypingImplCopyWithImpl<_$P2PEvent_PeerTypingImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String peerId, String addr) nodeDiscovered,
    required TResult Function(String peerId) nodeExpired,
    required TResult Function(String peerId, String displayName) nodeVerified,
    required TResult Function(String peerId) nodeOffline,
    required TResult Function(String peerId, UserInfoJson userInfo)
    userInfoReceived,
    required TResult Function(String from, ChatMessageJson message)
    messageReceived,
    required TResult Function(String to, String messageId) messageSent,
    required TResult Function(String from, bool isTyping) peerTyping,
  }) {
    return peerTyping(from, isTyping);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String peerId, String addr)? nodeDiscovered,
    TResult? Function(String peerId)? nodeExpired,
    TResult? Function(String peerId, String displayName)? nodeVerified,
    TResult? Function(String peerId)? nodeOffline,
    TResult? Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult? Function(String from, ChatMessageJson message)? messageReceived,
    TResult? Function(String to, String messageId)? messageSent,
    TResult? Function(String from, bool isTyping)? peerTyping,
  }) {
    return peerTyping?.call(from, isTyping);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String peerId, String addr)? nodeDiscovered,
    TResult Function(String peerId)? nodeExpired,
    TResult Function(String peerId, String displayName)? nodeVerified,
    TResult Function(String peerId)? nodeOffline,
    TResult Function(String peerId, UserInfoJson userInfo)? userInfoReceived,
    TResult Function(String from, ChatMessageJson message)? messageReceived,
    TResult Function(String to, String messageId)? messageSent,
    TResult Function(String from, bool isTyping)? peerTyping,
    required TResult orElse(),
  }) {
    if (peerTyping != null) {
      return peerTyping(from, isTyping);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(P2PEvent_NodeDiscovered value) nodeDiscovered,
    required TResult Function(P2PEvent_NodeExpired value) nodeExpired,
    required TResult Function(P2PEvent_NodeVerified value) nodeVerified,
    required TResult Function(P2PEvent_NodeOffline value) nodeOffline,
    required TResult Function(P2PEvent_UserInfoReceived value) userInfoReceived,
    required TResult Function(P2PEvent_MessageReceived value) messageReceived,
    required TResult Function(P2PEvent_MessageSent value) messageSent,
    required TResult Function(P2PEvent_PeerTyping value) peerTyping,
  }) {
    return peerTyping(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult? Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult? Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult? Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult? Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult? Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult? Function(P2PEvent_MessageSent value)? messageSent,
    TResult? Function(P2PEvent_PeerTyping value)? peerTyping,
  }) {
    return peerTyping?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(P2PEvent_NodeDiscovered value)? nodeDiscovered,
    TResult Function(P2PEvent_NodeExpired value)? nodeExpired,
    TResult Function(P2PEvent_NodeVerified value)? nodeVerified,
    TResult Function(P2PEvent_NodeOffline value)? nodeOffline,
    TResult Function(P2PEvent_UserInfoReceived value)? userInfoReceived,
    TResult Function(P2PEvent_MessageReceived value)? messageReceived,
    TResult Function(P2PEvent_MessageSent value)? messageSent,
    TResult Function(P2PEvent_PeerTyping value)? peerTyping,
    required TResult orElse(),
  }) {
    if (peerTyping != null) {
      return peerTyping(this);
    }
    return orElse();
  }
}

abstract class P2PEvent_PeerTyping extends P2PEvent {
  const factory P2PEvent_PeerTyping({
    required final String from,
    required final bool isTyping,
  }) = _$P2PEvent_PeerTypingImpl;
  const P2PEvent_PeerTyping._() : super._();

  String get from;
  bool get isTyping;

  /// Create a copy of P2PEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$P2PEvent_PeerTypingImplCopyWith<_$P2PEvent_PeerTypingImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
