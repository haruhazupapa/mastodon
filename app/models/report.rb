# frozen_string_literal: true

class Report < ApplicationRecord
  belongs_to :account
  belongs_to :target_account, class_name: 'Account'
  belongs_to :action_taken_by_account, class_name: 'Account'

  default_value_for :comment, value: '', allows_nil: false # MySQL can not have default to text

  scope :unresolved, -> { where(action_taken: false) }
  scope :resolved,   -> { where(action_taken: true) }

  def statuses
    Status.where(id: status_ids)
  end
end
