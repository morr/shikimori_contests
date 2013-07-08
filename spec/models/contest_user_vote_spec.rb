require 'spec_helper'

describe ContestUserVote do
  context '#relations' do
    it { should belong_to :contest_vote }
    it { should belong_to :user }
  end
end
