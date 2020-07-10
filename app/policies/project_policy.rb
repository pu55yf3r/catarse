# frozen_string_literal: true

class ProjectPolicy < ApplicationPolicy

  attr_reader :user, :record, :params

  def initialize(user, record, params = {})
    @user = user
    @record = record
    @params = params
  end

  self::UserScope = Struct.new(:current_user, :user, :scope) do
    def resolve
      if current_user.try(:admin?) || current_user == user
        scope.without_state('deleted')
      else
        scope.without_state(%w[deleted draft rejected])
      end
    end
  end

  def create?
    done_by_owner_or_admin?
  end

  def push_to_online?
    done_by_owner_or_admin?
  end

  def update?
    create? && record.state != 'deleted'
  end

  def publish?
    done_by_owner_or_admin?
  end

  def publish_by_steps?
    done_by_owner_or_admin?
  end

  def validate_publish?
    done_by_owner_or_admin?
  end

  def permitted_attributes
    if user.present? && (user.admin? || (record.draft? || record.rejected?))
      p_attr = record.attribute_names.map(&:to_sym)
      p_attr << :all_tags
      p_attr << :all_public_tags
      p_attr << user_attributes
      p_attr << budget_attributes
      p_attr << posts_attributes
      p_attr << reward_attributes
      p_attr << goal_attributes
      p_attr << integrations_attributes
      p_attr << :content_rating if (user.admin? || (record.draft? || record.rejected?))

      p_attr.flatten

      # TODO: This code is to prevent not allowed
      # fields without admin for legacy dashboard
      unless user.admin?
        not_allowed = %i[
          audited_user_name audited_user_cpf audited_user_phone_number
          state origin_id service_fee total_installments
          recommended created_at updated_at expires_at all_tags
        ]
        p_attr.delete_if { |key| not_allowed.include?(key) }
      end

      p_attr << allow_conditionally

      p_attr
    else
      [:about_html, :online_days, :video_url, :cover_image, :uploaded_image, :headline, :budget, :city_id, :city,
        user_attributes, posts_attributes, budget_attributes, reward_attributes, integrations_attributes]
    end
  end

  def budget_attributes
    { budgets_attributes: %i[id name value _destroy] }
  end

  def user_attributes
    user_policy = UserPolicy.new(user, record.user)
    { user_attributes: user_policy.permitted_attributes }
  end

  def posts_attributes
    { posts_attributes: %i[_destroy title comment_html exclusive id] }
  end

  def reward_attributes
    attrs = { rewards_attributes: [:_destroy, :id, :maximum_contributions,
                                   :description, :deliver_at, :minimum_value, :title, :shipping_options, { shipping_fees_attributes: %i[_destroy id value destination] }] }

    attrs[:rewards_attributes].delete(:deliver_at) if record.waiting_funds? || record.failed? || record.successful?

    attrs
  end

  def goal_attributes
    attrs = { goals_attributes: [:_destroy, :id, :value,
                                   :description, :title ]}
    attrs
  end

  def integrations_attributes
    { integrations_attributes: [:_destroy, :name, :id, :data => [ :name ]]}
  end

  def allow_conditionally
    integrations = params[:integrations_attributes] || record.integrations
    service_fee = params[:service_fee]

    if service_fee.present? && integrations.present? && record.state == 'draft'
      
      solidarity_integration = integrations.find { |integration| integration[:name] === 'SOLIDARITY_SERVICE_FEE' } || integrations.find_by(name: 'SOLIDARITY_SERVICE_FEE')
      
      if solidarity_integration.present?
        min_service_fee = 0.04
        max_service_fee = 0.20
        accepted_fee = service_fee.to_f >= min_service_fee && service_fee.to_f <= max_service_fee
        return :service_fee if accepted_fee
      end
    end
  end
end
