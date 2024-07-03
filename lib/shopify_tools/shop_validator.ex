defmodule ShopifyTools.ShopValidator do
  @doc """
  This method makes user inputs safer by ensuring that a given shop value is a properly formatted Shopify shop domain.

  > **Note**: if you're using custom shop domains for testing, you can use the `customShopDomains` setting to add allowed domains.

  ## Return

  `string | null`

  The `shop` value if it is a properly formatted Shopify shop domain, otherwise `null`.
  """
  def validate_shop_url(shop) do
    shop_url = shop
    domains_regex = ["myshopify\\.com", "shopify\\.com", "myshopify\\.io"]

    shop_url_regex = ~r/^[a-zA-Z0-9][a-zA-Z0-9-_]*\.(#{Enum.join(domains_regex, "|")})[\/]*$/

    shop_admin_regex =
      ~r/^admin\.(#{Enum.join(domains_regex, "|")})\/store\/([a-zA-Z0-9][a-zA-Z0-9-_]*)$/

    is_shop_admin_url = Regex.match?(shop_admin_regex, shop_url)

    shop_url =
      if is_shop_admin_url do
        shop_admin_url_to_legacy_url(shop_url) || ""
      else
        shop_url
      end

    sanitized_shop =
      if Regex.match?(shop_url_regex, shop_url) do
        shop_url
      else
        nil
      end

    sanitized_shop
  end

  defp shop_admin_url_to_legacy_url(_shop_url) do
    # Implement this function based on your requirements
    nil
  end

  @base64regex ~r/^[0-9a-zA-Z+]+={0,2}$/
  @origins_regex ["myshopify\\.com", "shopify\\.com", "myshopify\\.io", "spin\\.dev"]

  def validate_host(host, throw_on_invalid \\ false) do
    sanitized_host = if Regex.match?(@base64regex, host), do: host, else: nil

    if sanitized_host do
      case decode_host(sanitized_host) do
        {:ok, decoded_host} ->
          case URI.parse("https://#{decoded_host}") do
            %URI{host: hostname} ->
              host_regex = ~r/\.#{Enum.join(@origins_regex, "|")}$$/
              if !Regex.match?(host_regex, hostname), do: sanitized_host = nil

            _ ->
              sanitized_host = nil
          end

        _ ->
          sanitized_host = nil
      end
    end

    if is_nil(sanitized_host) and throw_on_invalid do
      raise "Received invalid host argument"
    end

    sanitized_host
  end

  defp decode_host(host) do
    case Base.decode64(host) do
      {:ok, decoded_host} -> {:ok, decoded_host}
      _ -> {:error, "Invalid base64 host"}
    end
  end
end
