use Mix.Config

config :ex_oauth2_provider, ExOauth2Provider,
  repo: ExOauth2Provider.Test.Repo,
  resource_owner: Dummy.User,
  default_scopes: ~w(public),
  optional_scopes: ~w(read write),
  password_auth: {ExOauth2Provider.Test.Auth, :auth},
  use_refresh_token: true,
  revoke_refresh_token_on_use: true,
  grant_flows: ~w(authorization_code client_credentials)

if System.get_env("UUID") == "all" do
  config :ex_oauth2_provider, ExOauth2Provider, app_schema: Dummy.UUIDSchema
end

config :ex_oauth2_provider, ecto_repos: [ExOauth2Provider.Test.Repo]

config :ex_oauth2_provider, ExOauth2Provider.Test.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ex_oauth2_provider_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "priv/test"
