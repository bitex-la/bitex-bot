namespace :arbitrage_bots do
  %w{start stop restart}.each do |action|
    desc "#{action.capitalize} all arbitrage bots"
    task action do
      on roles(:all) do
        sudo 'systemctl', action, 'arbitrage_bots.target'
      end
    end
  end
  after "deploy", "restart"
end

