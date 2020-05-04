
module Peatio
  module Waves
    # TODO: Processing of unconfirmed transactions from mempool isn't supported now.
    class Blockchain < Peatio::Blockchain::Abstract

      DEFAULT_FEATURES = {case_sensitive: true, cash_addr_format: false}.freeze
      UndefinedCurrencyError = Class.new(StandardError)

      def initialize(custom_features = {})
        @features = DEFAULT_FEATURES.merge(custom_features).slice(*SUPPORTED_FEATURES)
        @settings = {}
      end

      def configure(settings = {})
        # Clean client state during configure.
        @client = nil
        @token = []; @eth = []
        @settings.merge!(settings.slice(*SUPPORTED_SETTINGS))
        @settings[:currencies]&.each do |c|
          if c.dig(:options, :erc20_contract_address).present?
            @token << c
          else
            @eth << c
          end
        end
      end

      def fetch_block!(block_number)
        block_hash = client.client(:get, "blocks/at/#{block_number}")

        block_hash
          .fetch('transactions').each_with_object([]) do |tx, txs_array|
          txs = build_transaction(tx).map do |ntx|
            Peatio::Transaction.new(ntx.merge(block_number: block_number))
          end
          txs_array.append(*txs)
        end.yield_self { |txs_array| Peatio::Block.new(block_number, txs_array) }
      rescue Client::Error => e
        raise Peatio::Blockchain::ClientError, e
      end

      def latest_block_number
        client.client(:get, 'blocks/height')
            .fetch('height')
      rescue Client::Error => e
        raise Peatio::Blockchain::ClientError, e
      end

      def load_balance_of_address!(address, currency_id)
        currency = settings[:currencies].find { |c| c[:id] == currency_id.to_s }
        raise UndefinedCurrencyError unless currency

        if currency.dig(:options, :erc20_contract_address).present?
          address_with_balance = load_token_balance(address, currency)
        else
          address_with_balance = client.client(:get, "addresses/balance/#{address}")
              .fetch('balance')
              .to_d
              .yield_self { |amount| convert_from_base_unit(amount, currency) }
        end

        if address_with_balance.blank?
          raise Peatio::Blockchain::UnavailableAddressBalanceError, address
        end

        address_with_balance
      rescue Client::Error => e
        raise Peatio::Blockchain::ClientError, e
      end

      private

      def load_token_balance(address, currency)
        client.client(:get, "assets/balance/#{address}/#{contract_address}")
            .fetch('balance')
            .to_d
            .yield_self { |amount| convert_from_base_unit(amount, currency) }
      end

      def build_transaction(tx_data)
        return [] if tx_data['type'] != 4
        return [] if tx_data['amount'] < 0.to_d
        formatted_txs = []
        if tx_data.has_key?('assetId') && tx_data.fetch('assetId') != nil
          currencies = @token.select { |c| c.dig(:options, :erc20_contract_address) == tx_data.fetch('assetId') }
          currencies.map do |currency|
            formatted_txs << { hash: tx_data['id'],
              to_address: tx_data['recipient'],
              txout: 1,
              currency_id: currency.fetch(:id),
              amount: convert_from_base_unit(tx_data['amount'].to_d, currency),
              status: 'success'
            }
          end
        else
          @eth.map do |currency|
            puts tx_data['id']
            formatted_txs << { hash: tx_data['id'],
              to_address: tx_data['recipient'],
              txout: 1,
              currency_id: currency.fetch(:id),
              amount: convert_from_base_unit(tx_data['amount'].to_d, currency),
              status: 'success'
            }
          end
        end
        formatted_txs
      end

      def client
        @client ||= Client.new(settings_fetch(:server))
      end

      def settings_fetch(key)
        @settings.fetch(key) { raise Peatio::Blockchain::MissingSettingError, key.to_s }
      end

      def convert_from_base_unit(value, currency)
        value.to_d / currency.fetch(:base_factor).to_d
      end
    end
  end
end
