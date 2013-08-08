class ContestsController < ApplicationController
  before_filter :check_auth, only: [:new, :edit, :create, :update, :destroy]
  before_filter :prepare
  helper_method :breadcrumbs

  def current
    if user_signed_in?
      redirect_to Contest.current.select {|v| current_user.can_vote?(v) }.first || Contest.current.last || root_url
    else
      redirect_to Contest.current.last || root_url
    end
  end

  def index
    keywords 'аниме опросы турниры голосования'
    description 'Аниме опросы и турниры сайта'

    contests = Contest.order('id desc').all
    @created = contests.select(&:created?)
    @active = contests.select(&:started?)
    @finished = contests.select(&:finished?)
  end

  def show
    noindex if params[:round] || params[:vote]
    if @contest.to_param != params[:id]
      redirect_to url_for(@contest), status: :moved_permanently and return
    end

    keywords 'аниме опрос турнир голосование ' + @contest.title
    description 'Примите участие в аниме-турнире на нашем сайте и внесите свой вклад в голосование, мы хотим определить ' + Unicode::downcase(@contest.title) + '.'

    @contest = present @contest

    @page_title << @contest.title
    @page_title << @contest.displayed_round.title if params[:round]
  end

  # проголосовавшие в раунде
  def users
    noindex

    @contest = present @contest
    @page_title << @contest.title
    @page_title << @contest.displayed_round.title
    @page_title << 'Голоса'

    raise NotFound, "not finished round #{@contest.displayed_round.id}" unless @contest.displayed_vote.finished? || (user_signed_in? && current_user.admin?)
  end

  # турнирная сетка
  def grid
    noindex

    @contest = present @contest

    @page_title << @contest.title
    @page_title << 'Турнирная сетка'

    render 'grid', layout: false
  end

  def edit
    @page_title << "Изменение опроса"
  end

  def new
    @page_title << "Новый опрос"
    @contest ||= Contest.new

    @contest.started_on ||= Date.today + 1.day
    @contest.votes_per_round ||= 6
    @contest.vote_duration ||= 2
    @contest.vote_interval ||= 1
  end

  def create
    @contest = Contest.new params[:contest]
    @contest.user_id = current_user.id

    if @contest.save
      redirect_to edit_contest_url(@contest)
    else
      new and render :new
    end
  end

  def update
    if @contest.created? && params[:animes]
      @contest.animes = []
      params[:animes].map(&:to_i).select {|v| v != 0 }.each do |v|
        @contest.animes << Anime.find(v)
      end
    end

    if @contest.update_attributes params[:contest]
      # сброс сгенерённых
      @contest.prepare if @contest.can_start? && @contest.rounds.any?

      redirect_to edit_contest_url(@contest)
    else
      edit and render :edit
    end
  end

  # запуск контеста
  def start
    @contest.start
    redirect_to edit_contest_url(@contest)
  end

  # остановка контеста
  #def finish
    #@contest.finish
    #redirect_to edit_contest_url(@contest)
  #end

  # создание голосований
  def build
    @contest.prepare if @contest.created?
    redirect_to edit_contest_url(@contest)
  end

private
  def prepare
    @page_title = ["Опросы"]
    @contest ||= Contest.find params[:id] if params[:id]
  end

  # хлебные крошки
  def breadcrumbs
    crumbs = { 'Опросы' => contests_url }
    crumbs[@contest.title] = contest_url @contest if params[:action] == 'edit' && !@contest.created?
    crumbs[@contest.title] = contest_url @contest.entry if params[:action] == 'grid' && !@contest.created?
    crumbs[@contest.title] = contest_url @contest.entry if params[:round].present?

    if params[:action] == 'users'
      crumbs[@contest.title] = contest_url @contest.entry
      crumbs[@contest.displayed_round.title] = round_contest_url @contest.entry, round: @contest.displayed_round
    end
    crumbs
  end

  def check_auth
    authenticate_user!
    raise Forbidden unless current_user.contests_moderator?
  end
end
