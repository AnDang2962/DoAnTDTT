import { HttpsError, CallableRequest } from 'firebase-functions/v2/https';

export interface AuthContext {
  uid: string;
  email?: string;
  name?: string;
}

/**
 * Bắt buộc user phải đăng nhập (Google Sign-In hoặc bất kỳ Firebase Auth provider nào).
 * Firebase tự verify ID token trước khi function chạy → ta chỉ cần check request.auth.
 *
 * Throw HttpsError('unauthenticated') nếu chưa login.
 */
export function requireAuth(request: CallableRequest): AuthContext {
  if (!request.auth) {
    throw new HttpsError(
      'unauthenticated',
      'Bạn phải đăng nhập (Google Sign-In) trước khi gọi API này.'
    );
  }
  return {
    uid: request.auth.uid,
    email: request.auth.token.email as string | undefined,
    name: request.auth.token.name as string | undefined,
  };
}
