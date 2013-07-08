class ContestUserVote < ActiveRecord::Base
  belongs_to :contest_vote
  belongs_to :user
end
