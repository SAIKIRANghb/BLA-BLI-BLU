/// `Resource` - the tiny "remote slot" every async read/write flows through.
///
/// Redux-style: a slice of state is never `null`, it always knows *where it is*
/// (`idle` / `loading` / `success` / `error`), keeps the last good `value` so a
/// refresh does not blank the screen, and carries the last `error` message.
library;

import 'package:flutter/foundation.dart' show immutable;

enum LoadStatus { idle, loading, success, error }

@immutable
class Resource<T> {
  const Resource({this.status = LoadStatus.idle, this.value, this.error});

  /// Never-loading slot with an optional pre-filled value (optimistic seeds).
  const Resource.seeded(T this.value) : status = LoadStatus.success, error = null;

  final LoadStatus status;

  /// Last successfully loaded value - retained while [status] is `error`.
  final T? value;

  /// Human readable failure message (already translated by the API layer).
  final String? error;

  bool get hasValue => value != null;
  bool get isLoading => status == LoadStatus.loading;
  bool get isSuccess => status == LoadStatus.success;
  bool get isError => status == LoadStatus.error;

  /// First load (nothing to show yet) - show a skeleton.
  bool get showSkeleton => isLoading && !hasValue;

  Resource<T> toLoading() => Resource<T>(status: LoadStatus.loading, value: value);

  Resource<T> toSuccess(T next) => Resource<T>(status: LoadStatus.success, value: next);

  Resource<T> toError(String message) => Resource<T>(status: LoadStatus.error, value: value, error: message);

  Resource<T> toIdle() => Resource<T>(status: LoadStatus.idle, value: value);

  /// Identity on the payload: models are immutable value objects, so an
  /// unchanged value (same instance, or `==`) keeps the slot - and therefore
  /// every widget selecting it - from rebuilding.
  @override
  bool operator ==(Object other) =>
      other is Resource<T> && other.status == status && other.error == error && other.value == value;

  @override
  int get hashCode => Object.hash(status, error, value);

  @override
  String toString() => 'Resource<$T>($status, error: $error)';
}
