"""Erreurs API normalisées : chaque erreur porte un code stable et un
message compréhensible — jamais de secrets ni de trace technique côté client.
"""


class ApiError(Exception):
    def __init__(self, code: str, message: str, status: int = 400):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


def bad_input(message: str = "Requête invalide.") -> ApiError:
    return ApiError("INVALID_INPUT", message, 422)


def unauthorized(message: str = "Session expirée. Reconnectez-vous.") -> ApiError:
    return ApiError("UNAUTHORIZED", message, 401)


def source_not_found() -> ApiError:
    return ApiError("SOURCE_NOT_FOUND", "Source introuvable sur Telegram.", 404)


def source_inaccessible() -> ApiError:
    return ApiError(
        "SOURCE_INACCESSIBLE",
        "Cette source n'est pas accessible à votre compte Telegram.",
        403,
    )


def forbidden(message: str = "Compte non autorisé.") -> ApiError:
    return ApiError("FORBIDDEN", message, 403)


def invalid_code() -> ApiError:
    return ApiError("PHONE_CODE_INVALID", "Code de connexion incorrect.", 400)


def two_step_needed() -> ApiError:
    return ApiError(
        "TWO_STEP_NEEDED",
        "Un mot de passe en deux étapes est requis sur ce compte.",
        400,
    )


def not_connected() -> ApiError:
    return ApiError("NOT_CONNECTED", "Compte Telegram non connecté.", 400)


def telegram_error(detail: str) -> ApiError:
    return ApiError("TELEGRAM_ERROR", f"Erreur Telegram : {detail}", 502)


def flood(seconds: int) -> ApiError:
    return ApiError(
        "FLOOD",
        f"Trop de requêtes envoyées à Telegram. Réessayez dans {seconds} s.",
        429,
    )
