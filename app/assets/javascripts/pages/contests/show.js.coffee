# скрытие картинки для share в соц сетях
$('#social_image').hide()

$ ->
  # отображалка новых комментариев
  if IS_LOGGED_IN
    window.comments_notifier = new CommentsNotifier()
    entry_block_a = '.entry-block a'
  else
    entry_block_a = '.entry-block > a > div'

  # выбор первого голосования в списке
  vote_id = $('.vote-container').data('id')
  $vote = if vote_id
    $('.vote-link[data-id='+vote_id+']')
  else
    $('.vote-link.pending').first()

  $vote = $('.vote-link').first() unless $vote.length
  $vote.trigger 'click'
  $.hideCursorMessage()

  # показ тултипов результатов
  $('.results .uninitialized-tooltip').tooltip(ANIME_TOOLTIP_OPTIONS)
      .removeClass('uninitialized-tooltip')
  $(entry_block_a).each ->
    $(@).data('no-align', true).tooltip().onBeforeShow().show()
  $(entry_block_a+', .entry-block .entry-tooltip').off 'mouseenter mouseleave'

# голосование загружено
$(document.body).on 'ajax:success', '.vote-container', (e) ->
  # подсветка по ховеру курсора
  $('.vote-variant', e.target).hover ->
    unless $('.vote-variant.voted', e.target).length
      $('.vote-variant', e.target).addClass 'unhovered'
      $(@).removeClass('unhovered')
          .addClass 'hovered'
  , ->
    $('.vote-variant', e.target).removeClass 'hovered unhovered'

  # пометка проголосованным, если это указано
  variant = $('.vote', e.target).data 'voted'
  if variant
    $('.refrain', e.target).trigger 'ajax:success'

  # включение/отключение предложения воздержаться
  if $('.vote', e.target).data('state') == 'started'
    $('.item-content .warning').show()
  else
    $('.item-content .warning').hide()

  process_current_dom()

# клик по одному из вариантов голосования
$(document.body).on 'click', '.vote-variant img', (e) ->
  return if in_new_tab(e)
  state = $(e.target).closest('.vote').data 'state'
  if state == 'started'
    $(e.target).closest('.vote-variant').callRemote()
  false

# успешное голосование за один из вариантов
$(document.body).on 'ajax:success', '.vote-variant, .refrain', (e, data) ->
  $contest = $('.contest')
  # скрываем всё
  $('.help, .refrained, .next, .refrain', $contest).hide()
  # убираем помеченное проголосованным
  $('.vote-variant', $contest).removeClass 'voted'

  # это аякс запрос голосования
  if data
    data.ajax = true
  else
  # это просто загруженное голосование
    $vote = $(e.target).closest('.vote')
    data =
      ajax: false
      variant: $vote.data 'voted'
      vote_id: $vote.data 'vote_id'

  switch data.variant
    when 'none'
      # показываем, что воздержались
      $('.refrained', $contest).show()

    when 'left', 'right'
      # показываем, что проголосовали
      $('.refrain', $contest).show()
      $('.help.success', $contest).show()
      # помечаем проголосованный вариант
      $('.vote-variant[data-variant='+data.variant+']', $contest).addClass 'voted'

  # помечаем проголосованное голосование
  $link = $('.vote-link[data-id='+data.vote_id+']', $contest)
  if $link.hasClass 'pending'
    $link.removeClass('pending').addClass 'voted'

  # не проголосованные голосования
  $vote = $('.vote-link.pending', $contest).first()

  # если есть
  if $vote.length
    if data.ajax
      # и грузим следующее голосование
      _.delay ->
        $vote.first().trigger 'click'
    else
      # показываем ссылку "перейти дальше"
      $('.next', $contest).show()

  # или показываем "спасибо"
  else
    $('.finish', $contest).show()
    # и скрываем в верхнем меню иконку
    if data.ajax
      $('.userbox .contest[data-count=1]').hide()

# клик на переход к следующей паре
$(document.body).on 'click', '.vote-container .next', ->
  $('.vote-link.pending').first().trigger 'click'

# переключение между голосованиями
$(document.body).on 'ajax:before', '.vote-link', (e, data) ->
  unless $('.vote-container > img').length
    $('.vote-container').stop(true, false).animate opacity: 0.3

$(document.body).on 'ajax:success', '.vote-link', (e, data) ->
  $('.vote-link').removeClass 'active'
  $(e.target).addClass('active')

  $('.vote-container').html(data)
      .stop(true, false)
      .trigger('ajax:success')
      .animate opacity: 1
