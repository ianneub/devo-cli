# Devo-cli

This simple Ruby based CLI will launch a docker container on an ECS container instance with the same role and env vars as an ECS task definition. It effective duplicates the functionality of the `heroku run` command.

## Notice

NOTE: This script was hacked together in an afternoon, and should be treated as nothing more than an experimental prototype. Your results may vary.

## Usage

`devo run <command>`

## Example:

`devo run --cluster default --task_definition web rails db:migrate`

`devo run --cluster default --task_definition web rails console`
