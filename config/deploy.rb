# config valid only for current version of Capistrano
lock '3.4.1'

app_name = 'bitex-bot'
set :application, app_name
set :repo_url, "git@github.com:bitex-la/#{app_name}.git"

set :user, 'ubuntu'
set :deploy_to, "/home/ubuntu/apps/#{app_name}"
ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }.call
set(:ssh_options, fetch(:ssh_options, {})
  .merge!(
    forward_agent: true,
    user: fetch(:user),
    keepalive: true,
    keepalive_interval: 30
  ))

set :rbenv_ruby, File.read(File.expand_path('../.ruby-version', __dir__)).strip
