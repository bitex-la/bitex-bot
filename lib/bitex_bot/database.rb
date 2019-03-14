module BitexBot
  module Database
    ActiveRecord::Base.establish_connection(Settings.database.merge(reconnect: true))

    ActiveRecord::Schema.define(version: 1) do
      if ActiveRecord::Base.connection.tables.empty?
        create_table :buy_opening_flows do |t|
          t.decimal    :price,                   precision: 30, scale: 15
          t.decimal    :value_to_use,            precision: 30, scale: 15
          t.decimal    :suggested_closing_price, precision: 30, scale: 15
          t.integer    :order_id,                null: false
          t.string     :status,                  null: false,   default: 'executing'
          t.index      :status
          t.timestamps null: true
        end
        add_index :buy_opening_flows, :order_id

        create_table :sell_opening_flows do |t|
          t.decimal    :price,                   precision: 30, scale: 15
          t.decimal    :value_to_use,            precision: 30, scale: 15
          t.decimal    :suggested_closing_price, precision: 30, scale: 15
          t.integer    :order_id,                null: false
          t.string     :status,                  null: false,   default: 'executing'
          t.index      :status
          t.timestamps null: true
        end
        add_index :sell_opening_flows, :order_id

        create_table :open_buys do |t|
          t.belongs_to :opening_flow
          t.belongs_to :closing_flow
          t.decimal    :price,         precision: 30, scale: 15
          t.decimal    :amount,        precision: 30, scale: 15
          t.decimal    :quantity,      precision: 30, scale: 15
          t.integer    :transaction_id
          t.timestamps null: true
        end
        add_index :open_buys, :transaction_id

        create_table :open_sells do |t|
          t.belongs_to :opening_flow
          t.belongs_to :closing_flow
          t.decimal    :price,         precision: 30, scale: 15
          t.decimal    :quantity,      precision: 30, scale: 15
          t.decimal    :amount,        precision: 30, scale: 15
          t.integer    :transaction_id
          t.timestamps null: true
        end
        add_index :open_sells, :transaction_id

        create_table :buy_closing_flows do |t|
          t.decimal    :desired_price, precision: 30, scale: 15
          t.decimal    :quantity,      precision: 30, scale: 15
          t.decimal    :amount,        precision: 30, scale: 15
          t.boolean    :done,          null: false,   default: false
          t.decimal    :crypto_profit, precision: 30, scale: 15
          t.decimal    :fiat_profit,   precision: 30, scale: 15
          t.decimal    :fx_rate,       precision: 20, scale: 8
          t.timestamps null: true
        end

        create_table :sell_closing_flows do |t|
          t.decimal    :desired_price, precision: 30, scale: 15
          t.decimal    :quantity,      precision: 30, scale: 15
          t.decimal    :amount,        precision: 30, scale: 15
          t.boolean    :done,          null: false,   default: false
          t.decimal    :crypto_profit, precision: 30, scale: 15
          t.decimal    :fiat_profit,   precision: 30, scale: 15
          t.decimal    :fx_rate,       precision: 20, scale: 8
          t.timestamps null: true
        end

        create_table :close_buys do |t|
          t.belongs_to :closing_flow
          t.decimal    :amount,      precision: 30, scale: 15
          t.decimal    :quantity,    precision: 30, scale: 15
          t.string     :order_id,    null: false
          t.timestamps null: true
        end
        add_index :close_buys, :order_id

        create_table :close_sells do |t|
          t.belongs_to :closing_flow
          t.decimal    :amount,      precision: 30, scale: 15
          t.decimal    :quantity,    precision: 30, scale: 15
          t.string     :order_id,    null: false
          t.timestamps null: true
        end
        add_index :close_sells, :order_id
      end

      unless ActiveRecord::Base.connection.table_exists?('stores')
        create_table   :stores, force: true do |t|
          t.decimal    :maker_crypto,                       precision: 20,   scale: 8
          t.decimal    :maker_fiat,                         precision: 20,   scale: 8

          t.decimal    :taker_crypto,                       precision: 20,   scale: 8
          t.decimal    :taker_fiat,                         precision: 20,   scale: 8

          t.decimal    :crypto_stop,                        precision: 20,   scale: 8
          t.decimal    :crypto_warning,                     precision: 20,   scale: 8

          t.decimal    :fiat_stop,                          precision: 20,   scale: 8
          t.decimal    :fiat_warning,                       precision: 20,   scale: 8

          t.decimal    :buying_amount_to_spend_per_order,   precision: 20,   scale: 8
          t.decimal    :buying_fx_rate,                     precision: 20,   scale: 8
          t.decimal    :buying_profit,                      precision: 20,   scale: 8

          t.decimal    :selling_quantity_to_sell_per_order, precision: 20,   scale: 8
          t.decimal    :selling_fx_rate,                    precision: 20,   scale: 8
          t.decimal    :selling_profit,                     precision: 20,   scale: 8

          t.boolean    :hold,                               default:   false
          t.text       :log
          t.datetime   :last_warning

          t.timestamps null: true
        end
      end
    end
  end
end
