defmodule ExOauth2Provider.AccessTokensTest do
  use ExOauth2Provider.TestCase

  alias ExOauth2Provider.Test.{ConfigHelpers, Fixtures, QueryHelpers}
  alias ExOauth2Provider.AccessTokens
  alias Dummy.OauthAccessTokens.OauthAccessToken

  setup do
    user = Fixtures.resource_owner()
    {:ok, %{user: user, application: Fixtures.application(resource_owner: user)}}
  end

  test "get_by_token/1", %{user: user} do
    assert {:ok, access_token} = AccessTokens.create_token(user)

    assert %OauthAccessToken{id: id} = AccessTokens.get_by_token(access_token.token)
    assert id == access_token.id
  end

  test "get_by_refresh_token/2", %{user: user} do
    assert {:ok, access_token} = AccessTokens.create_token(user, %{use_refresh_token: true})

    assert %OauthAccessToken{id: id} = AccessTokens.get_by_refresh_token(access_token.refresh_token)
    assert id == access_token.id
  end

  describe "get_by_previous_refresh_token_for/2" do
    test "with resource owner", %{user: user} do
      {:ok, old_access_token} = AccessTokens.create_token(user, %{use_refresh_token: true})
      {:ok, new_access_token} = AccessTokens.create_token(user, %{use_refresh_token: true, previous_refresh_token: old_access_token})

      assert %OauthAccessToken{id: id} = AccessTokens.get_by_previous_refresh_token_for(new_access_token)
      assert id == old_access_token.id

      refute AccessTokens.get_by_previous_refresh_token_for(old_access_token)

      {:ok, new_access_token_different_user} = AccessTokens.create_token(Fixtures.resource_owner(), %{use_refresh_token: true, previous_refresh_token: old_access_token})

      refute AccessTokens.get_by_previous_refresh_token_for(new_access_token_different_user)
    end

    test "with application", %{user: user, application: application} do
      {:ok, old_access_token} = AccessTokens.create_token(user, %{application: application, use_refresh_token: true})
      {:ok, new_access_token} = AccessTokens.create_token(user, %{application: application, use_refresh_token: true, previous_refresh_token: old_access_token})

      assert %OauthAccessToken{id: id} = AccessTokens.get_by_previous_refresh_token_for(new_access_token)
      assert id == old_access_token.id

      refute AccessTokens.get_by_previous_refresh_token_for(old_access_token)

      {:ok, new_access_token_different_user} = AccessTokens.create_token(Fixtures.resource_owner(), %{application: application, use_refresh_token: true, previous_refresh_token: old_access_token})
      refute AccessTokens.get_by_previous_refresh_token_for(new_access_token_different_user)

      new_application = Fixtures.application(resource_owner: user, uid: "new_app")
      {:ok, new_access_token_different_app} = AccessTokens.create_token(user, %{application: new_application, use_refresh_token: true, previous_refresh_token: old_access_token})

      refute AccessTokens.get_by_previous_refresh_token_for(new_access_token_different_app)
    end
  end

  describe "get_matching_token_for/2" do
    test "fetches", %{user: user, application: application} do
      {:ok, access_token1} = AccessTokens.create_token(user, %{application: application})

      assert %OauthAccessToken{id: id} = AccessTokens.get_matching_token_for(user, application, "public")
      assert id == access_token1.id

      {:ok, access_token2} = AccessTokens.create_token(user, %{application: application})

      assert %OauthAccessToken{id: id} = AccessTokens.get_matching_token_for(user, application, "public")
      assert id == access_token2.id

      inserted_at = QueryHelpers.timestamp(OauthAccessToken, :inserted_at, seconds: 1)
      QueryHelpers.change!(access_token1, inserted_at: inserted_at)

      assert %OauthAccessToken{id: id} = AccessTokens.get_matching_token_for(user, application, "public")
      assert id == access_token1.id
    end

    test "with different resource owner", %{user: user, application: application} do
      {:ok, _access_token} = AccessTokens.create_token(user, %{application: application})

      refute AccessTokens.get_matching_token_for(Fixtures.resource_owner(), application, nil)
    end

    test "with scope", %{user: user, application: application} do
      {:ok, access_token1} = AccessTokens.create_token(user, %{application: application, scopes: "public"})
      {:ok, access_token2} = AccessTokens.create_token(user, %{application: application, scopes: "read write"})

      assert %OauthAccessToken{id: id} = AccessTokens.get_matching_token_for(user, application, "public")
      assert id == access_token1.id

      assert %OauthAccessToken{id: id} = AccessTokens.get_matching_token_for(user, application, "write read")
      assert id == access_token2.id

      refute AccessTokens.get_matching_token_for(user, application, "other_read")
    end

    test "with expired access token", %{user: user, application: application} do
      {:ok, access_token} = AccessTokens.create_token(user, %{application: application, scopes: "public", expires_in: -1})

      refute AccessTokens.get_matching_token_for(user, application, "public")

      QueryHelpers.change!(access_token, expires_in: 1)

      assert %OauthAccessToken{id: id} = AccessTokens.get_matching_token_for(user, application, "public")
      assert id == access_token.id
    end
  end

  test "get_authorized_tokens_for/1", %{user: user, application: application} do
    {:ok, access_token} = AccessTokens.create_token(user, %{application: application})

    assert [%OauthAccessToken{id: id}] = AccessTokens.get_authorized_tokens_for(user)
    assert id == access_token.id

    QueryHelpers.change!(access_token, expires_in: -1)

    assert [%OauthAccessToken{id: id}] = AccessTokens.get_authorized_tokens_for(user)
    assert id == access_token.id

    AccessTokens.revoke(access_token)
    assert AccessTokens.get_authorized_tokens_for(user) == []

    assert AccessTokens.get_authorized_tokens_for(Fixtures.resource_owner()) == []
  end

  describe "create_token/2" do
    test "with valid attributes", %{user: user} do
      assert {:ok, access_token} = AccessTokens.create_token(user)
      assert access_token.resource_owner_id == user.id
      assert is_nil(access_token.application_id)
    end

    test "with resource owner and application", %{user: user, application: application} do
      {:ok, access_token} = AccessTokens.create_token(user, %{application: application})
      assert access_token.resource_owner_id == user.id
      assert access_token.application_id == application.id
    end

    test "adds random token", %{user: user} do
      {:ok, access_token} = AccessTokens.create_token(user)
      {:ok, access_token2} = AccessTokens.create_token(user)
      assert access_token.token != access_token2.token
    end

    test "with custom access token generator", %{user: user} do
      ConfigHelpers.set_config(:access_token_generator, {__MODULE__, :access_token_generator})

      {:ok, access_token} = AccessTokens.create_token(user, %{})
      assert access_token.token == "custom_generated-#{user.id}"
    end

    test "adds previous_refresh_token", %{user: user} do
      {:ok, old_access_token} = AccessTokens.create_token(user, %{use_refresh_token: true})
      {:ok, new_access_token} = AccessTokens.create_token(user, %{use_refresh_token: true, previous_refresh_token: old_access_token})
      assert new_access_token.previous_refresh_token == old_access_token.refresh_token
    end

    test "adds random refresh token", %{user: user} do
      {:ok, access_token} = AccessTokens.create_token(user, %{use_refresh_token: true})
      {:ok, access_token2} = AccessTokens.create_token(user, %{use_refresh_token: true})
      assert access_token.refresh_token != access_token2.refresh_token
    end

    test "doesn't add refresh token when disabled", %{user: user} do
      {:ok, access_token} = AccessTokens.create_token(user, %{use_refresh_token: false})
      assert is_nil(access_token.refresh_token)
    end

    test "with no scopes", %{user: user} do
      assert {:ok, access_token} = AccessTokens.create_token(user)
      assert access_token.scopes == "public"
    end

    test "with custom scopes", %{user: user} do
      assert {:ok, access_token} = AccessTokens.create_token(user, %{scopes: "read"})
      assert access_token.scopes == "read"
    end

    test "with invalid scopes", %{user: user} do
      assert {:error, changeset} = AccessTokens.create_token(user, %{scopes: "invalid"})
      assert changeset.errors[:scopes] == {"not in permitted scopes list: [\"public\", \"read\", \"write\"]", []}
    end
  end

  describe "create_token/2 with application scopes" do
    setup %{user: user, application: application} do
       application = Map.merge(application, %{scopes: "public app:write app:read"})

       %{user: user, application: application}
    end

    test "with no scopes", %{user: user, application: application} do
      assert {:ok, access_token} = AccessTokens.create_token(user, %{application: application})
      assert access_token.scopes == "public"
    end

    test "with custom scopes", %{user: user, application: application} do
      application = Map.merge(application, %{scopes: "app:read"})
      assert {:ok, access_token} = AccessTokens.create_token(user, %{scopes: "app:read", application: application})
      assert access_token.scopes == "app:read"
    end

    test "with invalid scopes", %{user: user, application: application} do
      application = Map.merge(application, %{scopes: "app:read"})
      assert {:error, changeset} = AccessTokens.create_token(user, %{application: application, scopes: "app:write"})
      assert changeset.errors[:scopes] == {"not in permitted scopes list: \"app:read\"", []}
    end
  end

  test "create_application_token/2", %{application: application} do
    {:ok, access_token} = AccessTokens.create_application_token(application)
    assert is_nil(access_token.resource_owner_id)
    assert access_token.application_id == application.id
  end

  describe "get_or_create_token/4" do
    test "gets existing token", %{user: user} do
      {:ok, access_token} = AccessTokens.get_or_create_token(user, nil, nil, %{})
      assert is_nil(access_token.application_id)
      assert access_token.resource_owner_id == user.id

      {:ok, access_token2} = AccessTokens.get_or_create_token(user, nil, nil, %{})
      assert access_token.id == access_token2.id

      QueryHelpers.change!(access_token, scopes: "write read")
      {:ok, access_token3} = AccessTokens.get_or_create_token(user, nil, "read write", %{})
      assert access_token.id == access_token3.id
    end

    test "with resource owner and application", %{user: user, application: application} do
      {:ok, access_token} = AccessTokens.get_or_create_token(user, application, nil, %{})
      assert access_token.application_id == application.id
      assert access_token.resource_owner_id == user.id

      {:ok, access_token2} = AccessTokens.get_or_create_token(user, application, nil, %{})
      assert access_token2.id == access_token.id

      QueryHelpers.change!(access_token, scopes: "read write")
      {:ok, access_token3} = AccessTokens.get_or_create_token(user, application, "read write", %{})
      assert access_token3.id == access_token.id
    end

    test "creates token when matching is revoked", %{user: user} do
      {:ok, access_token} = AccessTokens.get_or_create_token(user, nil, nil, %{})
      AccessTokens.revoke(access_token)
      {:ok, access_token2} = AccessTokens.get_or_create_token(user, nil, nil, %{})
      assert access_token2.id != access_token.id
    end

    test "creates token when matching has expired", %{user: user} do
      {:ok, access_token1} = AccessTokens.create_token(user, %{expires_in: 1})
      {:ok, access_token2} = AccessTokens.create_token(user, %{expires_in: 1})

      {:ok, access_token} = AccessTokens.get_or_create_token(user, nil, nil, %{})
      assert access_token.id == access_token2.id

      inserted_at = QueryHelpers.timestamp(access_token2.__struct__, :inserted_at, seconds: -access_token.expires_in)
      QueryHelpers.change!(access_token2, inserted_at: inserted_at)

      {:ok, access_token} = AccessTokens.get_or_create_token(user, nil, nil, %{})
      assert access_token.id == access_token1.id

      QueryHelpers.change!(access_token1, inserted_at: inserted_at)

      {:ok, access_token} = AccessTokens.get_or_create_token(user, nil, nil, %{})
      refute access_token.id in [access_token1.id, access_token2.id]
    end

    test "creates token when params are different", %{user: user} do
      {:ok, access_token} = AccessTokens.get_or_create_token(user, nil, nil, %{})

      {:ok, access_token2} = AccessTokens.get_or_create_token(Fixtures.resource_owner(), nil, nil, %{})
      assert access_token2.id != access_token.id

      another_application = Fixtures.application(uid: "another_application")
      {:ok, access_token3} = AccessTokens.get_or_create_token(user, another_application, nil, %{})
      assert access_token3.id != access_token.id

      {:ok, access_token4} = AccessTokens.get_or_create_token(user, nil, "read", %{})
      assert access_token4.id != access_token.id
    end
  end

  test "get_or_create_application_token/3", %{application: application} do
    {:ok, access_token} = AccessTokens.get_or_create_application_token(application, nil, %{})
    assert access_token.application_id == application.id
    assert is_nil(access_token.resource_owner_id)

    {:ok, access_token2} = AccessTokens.get_or_create_application_token(application, nil, %{})
    assert access_token2.id == access_token.id
  end

  describe "revoke/1" do
    test "revokes token", %{user: user} do
      {:ok, access_token} = AccessTokens.create_token(user)

      assert {:ok, access_token} = AccessTokens.revoke(access_token)
      assert AccessTokens.is_revoked?(access_token) == true
    end

    test "doesn't revoke revoked tokens", %{user: user} do
      {:ok, access_token} = AccessTokens.create_token(user)
      revoked_at = QueryHelpers.timestamp(OauthAccessToken, :revoked_at, seconds: -86_400)
      access_token = Map.merge(access_token, %{revoked_at: revoked_at})

      {:ok, access_token2} = AccessTokens.revoke(access_token)
      assert access_token2.revoked_at == access_token.revoked_at
    end
  end

  test "is_revoked?/1" do
    assert AccessTokens.is_revoked?(%OauthAccessToken{revoked_at: QueryHelpers.timestamp(OauthAccessToken, :revoked_at)})
    refute AccessTokens.is_revoked?(%OauthAccessToken{revoked_at: nil})
  end

  describe "is_accessible?/1" do
    test "with active" do
      access_token = %OauthAccessToken{expires_in: 1, revoked_at: nil, inserted_at: QueryHelpers.timestamp(OauthAccessToken, :inserted_at)}
      assert AccessTokens.is_accessible?(access_token)
    end

    test "when revoked" do
      access_token = %OauthAccessToken{expires_in: 1, revoked_at: QueryHelpers.timestamp(OauthAccessToken, :revoked_at), inserted_at: QueryHelpers.timestamp(OauthAccessToken, :inserted_at)}
      refute AccessTokens.is_accessible?(access_token)
    end

    test "when expired" do
      access_token = %OauthAccessToken{expires_in: 0, revoked_at: nil, inserted_at: QueryHelpers.timestamp(OauthAccessToken, :inserted_at)}
      refute AccessTokens.is_accessible?(access_token)

      inserted_at = QueryHelpers.timestamp(OauthAccessToken, :inserted_at, seconds: -2)
      access_token = %OauthAccessToken{expires_in: 1, revoked_at: nil, inserted_at: inserted_at}
      refute AccessTokens.is_accessible?(access_token)
    end

    test "when never expires" do
      access_token = %OauthAccessToken{expires_in: nil, revoked_at: nil, inserted_at: QueryHelpers.timestamp(OauthAccessToken, :inserted_at)}
      assert AccessTokens.is_accessible?(access_token)
    end

    test "when nil" do
      refute AccessTokens.is_accessible?(nil)
    end
  end

  def access_token_generator(opts) do
    "custom_generated-#{opts[:resource_owner_id]}"
  end
end
