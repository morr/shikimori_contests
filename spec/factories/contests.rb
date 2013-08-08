FactoryGirl.define do
  factory :contest do
    title "MyString"
    user
    strategy_type :double_elimination
    description "MyString2"
    started_on Date.today
    votes_per_round 999
    vote_duration 1
    vote_interval 1
    user_vote_key 'can_vote_1'

    factory :contest_with_3_animes do
      after(:create) do |contest|
        1.upto(3) { contest.animes << FactoryGirl.create(:anime) }
      end
    end

    factory :contest_with_5_animes do
      after(:create) do |contest|
        1.upto(5) { contest.animes << FactoryGirl.create(:anime) }
      end
    end

    factory :contest_with_8_animes do
      after(:create) do |contest|
        1.upto(8) { contest.animes << FactoryGirl.create(:anime) }
      end
    end

    factory :contest_with_19_animes do
      after(:create) do |contest|
        1.upto(19) { contest.animes << FactoryGirl.create(:anime) }
      end
    end
  end
end
