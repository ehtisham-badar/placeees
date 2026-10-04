export class AppError extends Error {
  constructor(
    public readonly code: string,
    public readonly status = 400,
    message?: string,
  ) {
    super(message ?? code);
  }
}

export const notFound = () => new AppError('not_found', 404);
export const forbidden = (code = 'forbidden') => new AppError(code, 403);
