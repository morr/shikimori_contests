FactoryGirl.define do
  factory :contest_vote do
    association :left, factory: :anime
    association :right, factory: :anime
    association :round, factory: :contest_round
  end
end
