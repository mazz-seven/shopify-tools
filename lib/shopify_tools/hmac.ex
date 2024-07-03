defmodule ShopifyTools.Hmac do
  @spec build_hmac(conn :: Plug.Conn.t(), shopify :: ShopifyTools.Shopify.t()) :: String.t()
  def build_hmac(%Plug.Conn{method: "GET"} = conn, shopify) do
    # hmac param takes precedence and is present in App load requests.
    # signature param is present in Shopify App proxy requests https://shopify.dev/apps/online-store/app-proxies
    {signature_param, query_string_joiner} =
      if Map.has_key?(conn.query_params, "hmac"), do: {"hmac", "&"}, else: {"signature", ""}

    query_string =
      conn.query_params
      |> Map.delete(signature_param)
      |> Enum.map_join(query_string_joiner, fn
        {"ids", value} ->
          # This absolutely rediculous solution: https://community.shopify.com/c/Shopify-Apps/Hmac-Verification-for-Bulk-Actions/m-p/590611#M18504
          ids =
            Enum.map(value, fn id ->
              "\"#{id}\""
            end)
            |> Enum.join(", ")

          "ids=[#{ids}]"

        {key, value} ->
          "#{key}=#{value}"
      end)

    :crypto.mac(
      :hmac,
      :sha256,
      shopify.client_secret,
      query_string
    )
    |> Base.encode16()
    |> String.downcase()
  end

  def build_hmac(%Plug.Conn{method: "POST"} = conn, shopify) do
    :crypto.mac(
      :hmac,
      :sha256,
      shopify.client_secret,
      conn.assigns[:raw_body]
    )
    |> Base.encode64()
    |> String.downcase()
  end

  @spec get_hmac(conn :: Plug.Conn.t()) :: String.t() | nil
  def get_hmac(%Plug.Conn{params: %{"hmac" => hmac}}), do: String.downcase(hmac)

  def get_hmac(%Plug.Conn{params: %{"signature" => signature}}), do: String.downcase(signature)

  def get_hmac(%Plug.Conn{} = conn) do
    with [hmac_header] <- Plug.Conn.get_req_header(conn, "x-shopify-hmac-sha256") do
      String.downcase(hmac_header)
    else
      _ -> nil
    end
  end

  def validate(conn, shopify) do
    expectd = build_hmac(conn, shopify)
    received = get_hmac(conn)

    IO.puts("expected #{expectd}")
    IO.puts("received #{received}")

    if expectd == received do
      {:ok,
       %{
         domain: Plug.Conn.get_req_header(conn, "x-shopify-shop-domain") |> List.first(),
         api_version: Plug.Conn.get_req_header(conn, "x-shopify-api-version") |> List.first(),
         hmac: Plug.Conn.get_req_header(conn, "x-shopify-hmac-sha256") |> List.first(),
         topic: Plug.Conn.get_req_header(conn, "x-shopify-topic") |> List.first(),
         webhook_id: Plug.Conn.get_req_header(conn, "x-shopify-webhook-id") |> List.first()
       }}
    else
      {:error, :not_match}
    end
  end
end
