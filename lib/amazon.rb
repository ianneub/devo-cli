require 'aws-sdk-ecs'
require 'aws-sdk-ec2'
require 'aws-sdk-ecr'
require 'securerandom'

module Amazon
	def find_ip_address!(cluster)
		ecs = Aws::ECS::Client.new
		ec2 = Aws::EC2::Client.new

		instance_arn = ecs.list_container_instances(cluster: cluster)[:container_instance_arns].first
		
		raise 'Unable to find instance' unless instance_arn

		resp = ecs.describe_container_instances cluster: cluster, container_instances: [instance_arn]
		instance_id = resp[:container_instances].first[:ec2_instance_id]

		raise 'Unable to find instance id' unless instance_id

		resp = ec2.describe_instances instance_ids: [instance_id]
		ip_addr = resp.reservations[0].instances[0].public_ip_address

		raise 'Unable to find IP address' unless ip_addr

		ip_addr
	end

	def find_task_data!(task_definition_prefix)
		ecs = Aws::ECS::Client.new

		task_arn = get_first_task_arn!(task_definition_prefix)
		task_definition = ecs.describe_task_definition(task_definition: task_arn).task_definition

		{
			image: find_image!(task_definition),
			environment: find_env_vars!(task_definition),
			role: find_role!(task_definition)
		}
	end

	def find_env_vars!(task_definition)
		task_definition.container_definitions.first.environment
	end

	def find_image!(task_definition)
		task_definition.container_definitions.first.image
	end

	def find_role!(task_definition)
		task_definition.task_role_arn
	end

	def get_first_task_arn!(task_definition_prefix)
		ecs = Aws::ECS::Client.new

		resp = ecs.list_task_definitions family_prefix: task_definition_prefix, sort: 'DESC'
		task_arn = resp.task_definition_arns.first

		raise 'Unable to find task_arn' unless task_arn

		task_arn
	end

	def get_aws_credentials!(role_arn)
		sts = Aws::STS::Client.new
		user = sts.get_caller_identity.arn.split('/')[-1]
		assumed_role = sts.assume_role(role_arn: role_arn, role_session_name: "#{user}-#{SecureRandom.uuid}")

		# confirm inside container:
		# puts Aws::STS::Client.new.get_caller_identity; puts ENV['AWS_ACCESS_KEY_ID'];1

		raise 'Unable to assume role' unless assumed_role

		assumed_role.credentials
	end

	def get_authorization_token
		ecr = Aws::ECR::Client.new
		data = ecr.get_authorization_token.authorization_data[0]
		user, password = Base64.decode64(data.authorization_token).split(':')
		{user: user, password: password, endpoint: data.proxy_endpoint}
	end
end
