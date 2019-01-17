namespace :check do
  desc "Make sure local git is in sync with remote."
  task :revision do
    on release_roles(:all) do
      unless `git rev-parse HEAD` == `git rev-parse origin/#{fetch(:branch)}`
        puts "WARNING: HEAD is not the same as origin/#{fetch(:branch)}"
        puts "Run `git push` to sync changes."
        exit
      end
    end
  end
  before "deploy", "check:revision"
end
