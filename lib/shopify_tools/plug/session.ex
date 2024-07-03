defmodule ShopifyTools.Plug.Session do
  require Logger

  import Plug.Conn

  alias ShopifyTools.ShopValidator

  # https://github.com/Shopify/shopify-app-js/blob/0bd38310c2686664faee8bd9145eca27c66ab9a0/packages/apps/shopify-app-remix/src/server/authenticate/admin/authenticate.ts#L159
  @doc """
  takes the session token from an embedded app request and validate it.

  https://shopify.dev/docs/apps/build/authentication-authorization/get-access-tokens/exchange-tokens
  """
  def create_session_token_context(conn, shopify) do
    token = get_token(conn) || Guardian.Plug.current_token(conn)
    Logger.debug("Attempting to authenticate session token: #{token}")

    if shopify.is_embedded_app do
      case ShopifyTools.Guardian.resource_from_token(token) do
        {:ok, shop, claims} ->
          Logger.debug("session token is: #{shop.url} claims: #{inspect(claims)}")

          session_id =
            if shopify.use_online_tokens,
              do: get_jwt_session_id(shop.url, claims["sub"]),
              else: get_offline_id(shop.url)

          {shop, claims, session_id, token}

        {:error, error} ->
          {:error, error}
      end
    else
      IO.puts("Needs to implement")
      raise "implement"
    end
  end

  def get_jwt_session_id(shop, sub) do
    "#{ShopValidator.validate_shop_url(shop)}_#{sub}"
  end

  def get_offline_id(shop) do
    "offline_#{ShopValidator.validate_shop_url(shop)}"
  end

  @doc """
  Whether the session is active. Active sessions have an access token that is not expired, and has has the given
  scopes if scopes is equal to a truthy value.  
  """
  def is_access_token_active(session) do
    # TODO: check for scope change
    expires = Map.get(session, "expires", 0)
    expires < DateTime.to_unix(DateTime.utc_now())
  end

  def exchange_token(shopify, session_token, shop, opts \\ []) do
    # https://shopify.dev/docs/apps/build/authentication-authorization/get-access-tokens/exchange-tokens
    is_online = Keyword.get(opts, :is_online, false)

    token_type =
      if is_online,
        do: "urn:shopify:params:oauth:token-type:online-access-token",
        else: "urn:shopify:params:oauth:token-type:offline-access-token"

    req =
      Req.new(
        url: build_external_url(["https://", shop, "/admin/oauth/access_token"]),
        json: %{
          grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
          subject_token_type: "urn:ietf:params:oauth:token-type:id_token",
          subject_token: session_token,
          client_id: shopify.client_id,
          client_secret: shopify.client_secret,
          requested_token_type: token_type
        },
        headers: [
          "Content-Type": "application/json",
          Accept: "application/json"
        ],
        decode_json: [keys: :atoms]
      )

    case Req.post(req) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        IO.inspect(body, label: :access_token)

        if is_online do
          expires = DateTime.to_unix(DateTime.utc_now()) + body.expires_in * 1000

          session_id =
            if shopify.is_embedded_app,
              do: get_jwt_session_id(shop, body.associated_user.id),
              # TODO: should generate random id
              else: "some-random-id"

          %{
            id: session_id,
            url: shop,
            expires: expires,
            access_token: body.access_token,
            scope: body.scope,
            is_online: is_online,
            associated_user: body.associated_user,
            associated_user_scope: body.associated_user_scope
          }
        else
          %{
            id: get_offline_id(shop),
            shop: shop,
            is_online: is_online,
            access_token: body.access_token,
            scope: body.scope
          }
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        IO.inspect(body, label: "exchange_token")
        nil

      {:error, error} ->
        IO.inspect(error, label: "exchange_token")
        nil
    end
  end

  def session(conn, opts) do
    token = get_token(conn) || Guardian.Plug.current_token(conn)
    Logger.info("session token: #{token}")

    case ShopifyTools.Guardian.resource_from_token(token) do
      {:ok, shop, claims} ->
        locale = get_locale(conn, claims)
        host = get_host(conn, claims)
        ShopifyTools.Plug.put_shop(conn, shop, host, locale)

      _ ->
        init_new_session(conn, opts)
    end
  end

  defp init_new_session(conn, opts) do
    expected_hmac = ShopifyTools.Hmac.build_hmac(conn)
    received_hmac = ShopifyTools.Hmac.get_hmac(conn)

    if expected_hmac == received_hmac do
      shop_url = conn.params["shop"]

      scope = Keyword.fetch!(opts, :scope)
      redirect_url = Keyword.fetch!(opts, :redirect_url)
      client_id = ShopifyTools.Plug.fetch_client_id(conn)

      install_url =
        "https://#{shop_url}/admin/oauth/authorize?client_id=#{client_id}&scope=#{scope}&redirect_uri=#{redirect_url}"

      html = Plug.HTML.html_escape(install_url)
      body = "<html><body>You are being <a href=\"#{html}\">redirected</a>.</body></html>"

      conn
      |> put_resp_header("location", install_url)
      |> put_resp_content_type("text/html")
      |> send_resp(conn.status || 302, body)
      |> halt()
    else
      conn |> send_resp(401, "Wrong!") |> halt()
    end
  end

  defp get_token(%Plug.Conn{params: %{"id_token" => token}}), do: token

  defp get_token(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      [] -> nil
      ["Bearer " <> token | []] -> token
      _ -> nil
    end
  end

  defp get_locale(%Plug.Conn{params: %{"locale" => locale}}, _token_claims), do: locale

  defp get_locale(_conn, token_claims),
    do: Map.get(token_claims, "loc", "en")

  defp get_host(%Plug.Conn{params: %{"host" => host}}, _token_claims), do: host

  defp get_host(_conn, token_claims),
    do: Map.get(token_claims, "host")

  defp build_external_url(path, query_params \\ %{}) do
    Path.join(path) <> "?" <> URI.encode_query(query_params)
  end
end
