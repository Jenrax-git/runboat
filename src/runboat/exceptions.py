class ClientError(Exception):
    pass


class RepoNotSupported(ClientError):
    pass


class BranchNotFound(ClientError):
    pass


class NotFoundOnGitHub(ClientError):
    pass


class RepoOrBranchNotSupported(ClientError):
    pass


class NoPreviousBuildError(ClientError):
    """No existe build previo del mismo branch/PR para copiar."""
