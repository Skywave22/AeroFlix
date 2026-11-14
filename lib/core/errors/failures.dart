import 'package:equatable/equatable.dart';

class Failure extends Equatable {
  final String code;
  final String message;
  final Object? cause;
  const Failure({required this.code, required this.message, this.cause});

  String toUserMessage() {
    switch (code) {
      case 'NETWORK':
        return 'No internet connection. Please check your network and try again.';
      case 'TIMEOUT':
        return 'The request took too long. Please try again.';
      case 'SITE_BLOCKED':
        return 'This source is blocked on your network. Try using a VPN.';
      case 'NOT_FOUND':
        return 'We couldn\'t find that title.';
      case 'NO_STREAMS':
        return 'No playable sources found for this title right now.';
      case 'SERVER':
        return 'The server returned an error. Please try again shortly.';
      case 'PARSE':
        return 'Something went wrong while reading the response.';
      case 'CANCELLED':
        return 'The request was cancelled.';
      default:
        return message.isNotEmpty ? message : 'Something went wrong.';
    }
  }

  factory Failure.network({Object? cause}) =>
      const Failure(code: 'NETWORK', message: 'Network error');
  factory Failure.timeout({Object? cause}) =>
      const Failure(code: 'TIMEOUT', message: 'Request timed out');
  factory Failure.notFound({String? message}) =>
      Failure(code: 'NOT_FOUND', message: message ?? 'Not found');
  factory Failure.noStreams() =>
      const Failure(code: 'NO_STREAMS', message: 'No streams available');
  factory Failure.server({String? message, Object? cause}) =>
      Failure(code: 'SERVER', message: message ?? 'Server error', cause: cause);
  factory Failure.parse({Object? cause}) =>
      const Failure(code: 'PARSE', message: 'Failed to parse response');
  factory Failure.cancelled() =>
      const Failure(code: 'CANCELLED', message: 'Cancelled');
  factory Failure.siteBlocked({Object? cause}) => Failure(
      code: 'SITE_BLOCKED',
      message: 'Source is blocked on your network',
      cause: cause);

  @override
  List<Object?> get props => [code, message, cause];
}
