eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
pyenv activate notion
bundle install
bundle exec foreman start
