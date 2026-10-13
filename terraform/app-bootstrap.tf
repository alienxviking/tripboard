# Things the application needs before Argo CD deploys it:
# the namespace (with Pod Security labels) and the database secret.
# The password is generated here and never written to git.

resource "kubernetes_namespace_v1" "tripboard" {
  metadata {
    name = "tripboard"
    labels = {
      "app.kubernetes.io/part-of"          = "tripboard"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "db" {
  metadata {
    name      = "tripboard-db"
    namespace = kubernetes_namespace_v1.tripboard.metadata[0].name
  }

  data = {
    POSTGRES_PASSWORD = random_password.db.result
    DATABASE_URL      = "postgresql+psycopg://tripboard:${random_password.db.result}@tripboard-postgres:5432/tripboard"
  }
}
