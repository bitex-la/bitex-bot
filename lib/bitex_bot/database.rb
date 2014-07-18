module BitexBot
  module Database
    #ActiveRecord::Base.logger = Logger.new(File.open('database.log', 'w'))
    ActiveRecord::Base.establish_connection(Settings.database)

    if ActiveRecord::Base.connection.tables.empty?
      ActiveRecord::Schema.define(version: 1) do
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
          t.integer :order_id
          t.timestamps
        end
        add_index :close_buys, :order_id

        create_table :close_sells do |t|
          t.belongs_to :closing_flow
          t.decimal :amount, precision: 30, scale: 15
          t.decimal :quantity, precision: 30, scale: 15
          t.integer :order_id
          t.timestamps
        end
        add_index :close_sells, :order_id
      end
    end
  end
end

