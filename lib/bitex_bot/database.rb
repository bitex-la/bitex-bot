module BitexBot
  module Database
    #ActiveRecord::Base.logger = Logger.new(File.open('database.log', 'w'))
    ActiveRecord::Base.establish_connection(Settings.database)

    ActiveRecord::Schema.define(version: 1) do
      if ActiveRecord::Base.connection.tables.empty?
        create_table :buy_opening_flows do |t|
          t.decimal :price, precision: 30, scale: 15
          t.decimal :value_to_use, precision: 30, scale: 15
          t.decimal :suggested_closing_price, precision: 30, scale: 15
          t.integer :order_id
          t.string :status, null: false, default: 'executing'
          t.index :status
          t.timestamps
        end
        add_index :buy_opening_flows, :order_id

        create_table :sell_opening_flows do |t|
          t.decimal :price, precision: 30, scale: 15
          t.decimal :value_to_use, precision: 30, scale: 15
          t.decimal :suggested_closing_price, precision: 30, scale: 15
          t.integer :order_id
          t.string :status, null: false, default: 'executing'
          t.index :status
          t.timestamps
        end
        add_index :sell_opening_flows, :order_id
        
        create_table :open_buys do |t|
          t.belongs_to :opening_flow
          t.belongs_to :closing_flow
          t.decimal :price, precision: 30, scale: 15
          t.decimal :amount, precision: 30, scale: 15
          t.decimal :quantity, precision: 30, scale: 15
          t.integer :transaction_id
          t.timestamps
        end
        add_index :open_buys, :transaction_id

        create_table :open_sells do |t|
          t.belongs_to :opening_flow
          t.belongs_to :closing_flow
          t.decimal :price, precision: 30, scale: 15
          t.decimal :quantity, precision: 30, scale: 15
          t.decimal :amount, precision: 30, scale: 15
          t.integer :transaction_id
          t.timestamps
        end
        add_index :open_sells, :transaction_id
        
        create_table :buy_closing_flows do |t|
          t.decimal :desired_price, precision: 30, scale: 15
          t.decimal :quantity, precision: 30, scale: 15
          t.decimal :amount, precision: 30, scale: 15
          t.boolean :done, null: false, default: false
          t.decimal :btc_profit, precision: 30, scale: 15
          t.decimal :usd_profit, precision: 30, scale: 15
          t.timestamps
        end

        create_table :sell_closing_flows do |t|
          t.decimal :desired_price, precision: 30, scale: 15
          t.decimal :quantity, precision: 30, scale: 15
          t.decimal :amount, precision: 30, scale: 15
          t.boolean :done, null: false, default: false
          t.decimal :btc_profit, precision: 30, scale: 15
          t.decimal :usd_profit, precision: 30, scale: 15
          t.timestamps
        end
        
        create_table :close_buys do |t|
          t.belongs_to :closing_flow
          t.decimal :amount, precision: 30, scale: 15
          t.decimal :quantity, precision: 30, scale: 15
          t.string :order_id
          t.timestamps
        end
        add_index :close_buys, :order_id

        create_table :close_sells do |t|
          t.belongs_to :closing_flow
          t.decimal :amount, precision: 30, scale: 15
          t.decimal :quantity, precision: 30, scale: 15
          t.string :order_id
          t.timestamps
        end
        add_index :close_sells, :order_id
      end

      unless ActiveRecord::Base.connection.column_exists?('stores', 'buying_profit')
        create_table "stores", force: true do |t|
          t.decimal  "taker_usd",                precision: 20, scale: 8
          t.decimal  "taker_btc",                precision: 20, scale: 8
          t.boolean  "hold", default: false
          t.text     "log"
          t.decimal  "usd_stop",  precision: 20, scale: 8
          t.decimal  "usd_warning",  precision: 20, scale: 8
          t.decimal  "btc_stop",  precision: 20, scale: 8
          t.decimal  "btc_warning",         precision: 20, scale: 8
          t.datetime "last_warning"
          t.decimal "buying_profit", precision: 20, scale: 8
          t.decimal "selling_profit", precision: 20, scale: 8
          t.timestamps
        end
      end
    end

  end
end

