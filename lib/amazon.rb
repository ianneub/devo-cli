# frozen_string_literal: true

require 'aws-sdk-autoscaling'
require 'aws-sdk-ecs'
require 'aws-sdk-ec2'
require 'aws-sdk-ecr'
require 'securerandom'

module Amazon
  def find_instance_id!(cluster)
    ecs = Aws::ECS::Client.new

    instance_arn = ecs.list_container_instances(cluster:)[:container_instance_arns].first

    raise 'Unable to find instance' unless instance_arn

    resp = ecs.describe_container_instances cluster:, container_instances: [instance_arn]

    instance_id = resp[:container_instances].first[:ec2_instance_id]
    raise 'Unable to find instance id' unless instance_id

    instance_id
  end

  def find_ip_address!(instance_id)
    ec2 = Aws::EC2::Client.new

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

  def find_runtime_id_and_ip!(cluster, service, container_name)
    output = []

    ecs = Aws::ECS::Client.new
    task_arns = ecs.list_tasks(cluster:, service_name: service).task_arns
    task = ecs.describe_tasks(cluster:, tasks: task_arns).tasks.first
    return nil unless task

    output << task.containers&.find{|c| c.name == container_name}&.runtime_id

    # find container instance id
    output << find_ip_address!(ecs.describe_container_instances(cluster:, container_instances: [task.container_instance_arn]).container_instances.first.ec2_instance_id)

    output
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
    assumed_role = sts.assume_role(role_arn:, role_session_name: "#{user}-#{SecureRandom.uuid}")

    # confirm inside container:
    # puts Aws::STS::Client.new.get_caller_identity; puts ENV['AWS_ACCESS_KEY_ID'];1

    raise 'Unable to assume role' unless assumed_role

    assumed_role.credentials
  end

  def authorization_token
    ecr = Aws::ECR::Client.new
    data = ecr.get_authorization_token.authorization_data[0]
    user, password = Base64.decode64(data.authorization_token).split(':')
    { user:, password:, endpoint: data.proxy_endpoint }
  end

  def find_all_running_instance_public_ip_addresses
    ec2 = Aws::EC2::Client.new
    out = ec2.describe_instances({
                                   filters: [
                                     {
                                       name: 'instance-state-name',
                                       values: ['running']
                                     }
                                   ]
                                 })
    out.reservations.map {|res| res.instances.map(&:public_ip_address) }.flatten
  end

  def instances_by_autoscaling_group
    out = Hash.new {|hash, key| hash[key] = [] }
    group_names = %w[ProductionECS ProductionECSSpot AuxECSSpot StagingECSSpot]
    group_names.each do |name|
      group = Aws::AutoScaling::AutoScalingGroup.new(name)
      group.instances.each do |instance|
        out[group] << instance
      end
    end
    out
  end

  def container_instances_by_ecs_cluster
    out = {}
    out['aux'] = []
    out['staging'] = []
    out['production'] = []

    client = Aws::ECS::Client.new
    out.each do |name, _|
      res = client.list_container_instances(cluster: name, status: 'ACTIVE')
      res.container_instance_arns.each do |arn|
        res = client.describe_container_instances(cluster: name, container_instances: [arn])
        out[name] << res.container_instances[0]
      end
    end
  end

  def container_instance_count(cluster)
    client = Aws::ECS::Client.new
    res = client.list_container_instances(cluster:, status: 'ACTIVE')
    res.container_instance_arns.length
  end

  def drain_container_instances(cluster, arns)
    client = Aws::ECS::Client.new
    client.update_container_instances_state(cluster:, status: 'DRAINING', container_instances: arns)
  end

  def container_instance_tasks_count(cluster, arn)
    client = Aws::ECS::Client.new
    res = client.describe_container_instances(cluster:, container_instances: [arn])
    res.container_instances[0].running_tasks_count
  end

  def terminate_instance(id)
    instance = Aws::EC2::Instance.new(id)
    instance.terminate
  end
end
