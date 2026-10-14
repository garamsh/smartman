// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'engine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$EngineError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'EngineError()';
}


}

/// @nodoc
class $EngineErrorCopyWith<$Res>  {
$EngineErrorCopyWith(EngineError _, $Res Function(EngineError) __);
}


/// Adds pattern-matching-related methods to [EngineError].
extension EngineErrorPatterns on EngineError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( EngineError_ReviewBeforeLastReview value)?  reviewBeforeLastReview,TResult Function( EngineError_UnknownRating value)?  unknownRating,TResult Function( EngineError_NonFinite value)?  nonFinite,TResult Function( EngineError_OutOfRange value)?  outOfRange,required TResult orElse(),}){
final _that = this;
switch (_that) {
case EngineError_ReviewBeforeLastReview() when reviewBeforeLastReview != null:
return reviewBeforeLastReview(_that);case EngineError_UnknownRating() when unknownRating != null:
return unknownRating(_that);case EngineError_NonFinite() when nonFinite != null:
return nonFinite(_that);case EngineError_OutOfRange() when outOfRange != null:
return outOfRange(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( EngineError_ReviewBeforeLastReview value)  reviewBeforeLastReview,required TResult Function( EngineError_UnknownRating value)  unknownRating,required TResult Function( EngineError_NonFinite value)  nonFinite,required TResult Function( EngineError_OutOfRange value)  outOfRange,}){
final _that = this;
switch (_that) {
case EngineError_ReviewBeforeLastReview():
return reviewBeforeLastReview(_that);case EngineError_UnknownRating():
return unknownRating(_that);case EngineError_NonFinite():
return nonFinite(_that);case EngineError_OutOfRange():
return outOfRange(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( EngineError_ReviewBeforeLastReview value)?  reviewBeforeLastReview,TResult? Function( EngineError_UnknownRating value)?  unknownRating,TResult? Function( EngineError_NonFinite value)?  nonFinite,TResult? Function( EngineError_OutOfRange value)?  outOfRange,}){
final _that = this;
switch (_that) {
case EngineError_ReviewBeforeLastReview() when reviewBeforeLastReview != null:
return reviewBeforeLastReview(_that);case EngineError_UnknownRating() when unknownRating != null:
return unknownRating(_that);case EngineError_NonFinite() when nonFinite != null:
return nonFinite(_that);case EngineError_OutOfRange() when outOfRange != null:
return outOfRange(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PlatformInt64 lastReview,  PlatformInt64 review)?  reviewBeforeLastReview,TResult Function( int value)?  unknownRating,TResult Function( Quantity quantity)?  nonFinite,TResult Function( Quantity quantity,  double value)?  outOfRange,required TResult orElse(),}) {final _that = this;
switch (_that) {
case EngineError_ReviewBeforeLastReview() when reviewBeforeLastReview != null:
return reviewBeforeLastReview(_that.lastReview,_that.review);case EngineError_UnknownRating() when unknownRating != null:
return unknownRating(_that.value);case EngineError_NonFinite() when nonFinite != null:
return nonFinite(_that.quantity);case EngineError_OutOfRange() when outOfRange != null:
return outOfRange(_that.quantity,_that.value);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PlatformInt64 lastReview,  PlatformInt64 review)  reviewBeforeLastReview,required TResult Function( int value)  unknownRating,required TResult Function( Quantity quantity)  nonFinite,required TResult Function( Quantity quantity,  double value)  outOfRange,}) {final _that = this;
switch (_that) {
case EngineError_ReviewBeforeLastReview():
return reviewBeforeLastReview(_that.lastReview,_that.review);case EngineError_UnknownRating():
return unknownRating(_that.value);case EngineError_NonFinite():
return nonFinite(_that.quantity);case EngineError_OutOfRange():
return outOfRange(_that.quantity,_that.value);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PlatformInt64 lastReview,  PlatformInt64 review)?  reviewBeforeLastReview,TResult? Function( int value)?  unknownRating,TResult? Function( Quantity quantity)?  nonFinite,TResult? Function( Quantity quantity,  double value)?  outOfRange,}) {final _that = this;
switch (_that) {
case EngineError_ReviewBeforeLastReview() when reviewBeforeLastReview != null:
return reviewBeforeLastReview(_that.lastReview,_that.review);case EngineError_UnknownRating() when unknownRating != null:
return unknownRating(_that.value);case EngineError_NonFinite() when nonFinite != null:
return nonFinite(_that.quantity);case EngineError_OutOfRange() when outOfRange != null:
return outOfRange(_that.quantity,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class EngineError_ReviewBeforeLastReview extends EngineError {
  const EngineError_ReviewBeforeLastReview({required this.lastReview, required this.review}): super._();
  

/// The card's last review.
 final  PlatformInt64 lastReview;
/// The refused review time.
 final  PlatformInt64 review;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineError_ReviewBeforeLastReviewCopyWith<EngineError_ReviewBeforeLastReview> get copyWith => _$EngineError_ReviewBeforeLastReviewCopyWithImpl<EngineError_ReviewBeforeLastReview>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError_ReviewBeforeLastReview&&(identical(other.lastReview, lastReview) || other.lastReview == lastReview)&&(identical(other.review, review) || other.review == review));
}


@override
int get hashCode {
    return Object.hash(runtimeType,lastReview,review);
}

@override
String toString() {
    return 'EngineError.reviewBeforeLastReview(lastReview: $lastReview, review: $review)';
}


}

/// @nodoc
abstract mixin class $EngineError_ReviewBeforeLastReviewCopyWith<$Res> implements $EngineErrorCopyWith<$Res> {
  factory $EngineError_ReviewBeforeLastReviewCopyWith(EngineError_ReviewBeforeLastReview value, $Res Function(EngineError_ReviewBeforeLastReview) _then) = _$EngineError_ReviewBeforeLastReviewCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 lastReview, PlatformInt64 review
});




}
/// @nodoc
class _$EngineError_ReviewBeforeLastReviewCopyWithImpl<$Res>
    implements $EngineError_ReviewBeforeLastReviewCopyWith<$Res> {
  _$EngineError_ReviewBeforeLastReviewCopyWithImpl(this._self, this._then);

  final EngineError_ReviewBeforeLastReview _self;
  final $Res Function(EngineError_ReviewBeforeLastReview) _then;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? lastReview = null,Object? review = null,}) {
  return _then(EngineError_ReviewBeforeLastReview(
lastReview: null == lastReview ? _self.lastReview : lastReview // ignore: cast_nullable_to_non_nullable
as PlatformInt64,review: null == review ? _self.review : review // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class EngineError_UnknownRating extends EngineError {
  const EngineError_UnknownRating({required this.value}): super._();
  

/// The refused number.
 final  int value;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineError_UnknownRatingCopyWith<EngineError_UnknownRating> get copyWith => _$EngineError_UnknownRatingCopyWithImpl<EngineError_UnknownRating>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError_UnknownRating&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'EngineError.unknownRating(value: $value)';
}


}

/// @nodoc
abstract mixin class $EngineError_UnknownRatingCopyWith<$Res> implements $EngineErrorCopyWith<$Res> {
  factory $EngineError_UnknownRatingCopyWith(EngineError_UnknownRating value, $Res Function(EngineError_UnknownRating) _then) = _$EngineError_UnknownRatingCopyWithImpl;
@useResult
$Res call({
 int value
});




}
/// @nodoc
class _$EngineError_UnknownRatingCopyWithImpl<$Res>
    implements $EngineError_UnknownRatingCopyWith<$Res> {
  _$EngineError_UnknownRatingCopyWithImpl(this._self, this._then);

  final EngineError_UnknownRating _self;
  final $Res Function(EngineError_UnknownRating) _then;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(EngineError_UnknownRating(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class EngineError_NonFinite extends EngineError {
  const EngineError_NonFinite({required this.quantity}): super._();
  

/// The quantity given.
 final  Quantity quantity;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineError_NonFiniteCopyWith<EngineError_NonFinite> get copyWith => _$EngineError_NonFiniteCopyWithImpl<EngineError_NonFinite>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError_NonFinite&&(identical(other.quantity, quantity) || other.quantity == quantity));
}


@override
int get hashCode {
    return Object.hash(runtimeType,quantity);
}

@override
String toString() {
    return 'EngineError.nonFinite(quantity: $quantity)';
}


}

/// @nodoc
abstract mixin class $EngineError_NonFiniteCopyWith<$Res> implements $EngineErrorCopyWith<$Res> {
  factory $EngineError_NonFiniteCopyWith(EngineError_NonFinite value, $Res Function(EngineError_NonFinite) _then) = _$EngineError_NonFiniteCopyWithImpl;
@useResult
$Res call({
 Quantity quantity
});




}
/// @nodoc
class _$EngineError_NonFiniteCopyWithImpl<$Res>
    implements $EngineError_NonFiniteCopyWith<$Res> {
  _$EngineError_NonFiniteCopyWithImpl(this._self, this._then);

  final EngineError_NonFinite _self;
  final $Res Function(EngineError_NonFinite) _then;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? quantity = null,}) {
  return _then(EngineError_NonFinite(
quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as Quantity,
  ));
}


}

/// @nodoc


class EngineError_OutOfRange extends EngineError {
  const EngineError_OutOfRange({required this.quantity, required this.value}): super._();
  

/// The quantity given.
 final  Quantity quantity;
/// The refused value.
 final  double value;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EngineError_OutOfRangeCopyWith<EngineError_OutOfRange> get copyWith => _$EngineError_OutOfRangeCopyWithImpl<EngineError_OutOfRange>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EngineError_OutOfRange&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,quantity,value);
}

@override
String toString() {
    return 'EngineError.outOfRange(quantity: $quantity, value: $value)';
}


}

/// @nodoc
abstract mixin class $EngineError_OutOfRangeCopyWith<$Res> implements $EngineErrorCopyWith<$Res> {
  factory $EngineError_OutOfRangeCopyWith(EngineError_OutOfRange value, $Res Function(EngineError_OutOfRange) _then) = _$EngineError_OutOfRangeCopyWithImpl;
@useResult
$Res call({
 Quantity quantity, double value
});




}
/// @nodoc
class _$EngineError_OutOfRangeCopyWithImpl<$Res>
    implements $EngineError_OutOfRangeCopyWith<$Res> {
  _$EngineError_OutOfRangeCopyWithImpl(this._self, this._then);

  final EngineError_OutOfRange _self;
  final $Res Function(EngineError_OutOfRange) _then;

/// Create a copy of EngineError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? quantity = null,Object? value = null,}) {
  return _then(EngineError_OutOfRange(
quantity: null == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as Quantity,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
