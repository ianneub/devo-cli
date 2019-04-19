# Devo-cli

This simple Ruby based CLI will launch a docker container on an ECS container instance with the same role and env vars as an ECS task definition. It effective duplicates the functionality of the `heroku run` command.

## Notice

NOTE: This script was hacked together in an afternoon, and should be treated as nothing more than an experimental prototype. Your results may vary.

It requires that your local environment contain enough information for the Ruby AWS SDK to authenticate with. It also requires that you have SSH installed locally as it will shell out to the SSH client.

## Usage

`devo run <command>`

## Example:

`devo run --cluster default --task_definition web rails db:migrate`

`devo run --cluster default --task_definition web rails console`
