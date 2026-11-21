enum TaskResultFilter { all, successOnly, failureOnly }

List<T> filterTaskResults<T>(
  Iterable<T> items, {
  required TaskResultFilter filter,
  required bool Function(T item) isSuccess,
  required bool Function(T item) isFailure,
}) {
  return switch (filter) {
    TaskResultFilter.all => items.toList(growable: false),
    TaskResultFilter.successOnly =>
      items.where((T item) => isSuccess(item)).toList(growable: false),
    TaskResultFilter.failureOnly =>
      items.where((T item) => isFailure(item)).toList(growable: false),
  };
}
