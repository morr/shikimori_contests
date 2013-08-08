$ ->
  $('.anime-suggest').make_completable 'Название аниме...', accept_complete

# сохранение опроса
$(document.body).on 'click', '.edit .save', ->
  $(@).parents('form').trigger 'submit'

# удаление элемента из опроса
$(document.body).on 'click', '.edit .item-minus', ->
  $(@).parent().remove()
  recalc_animes_count()
  #recalc_duration()

# автокомплит
accept_complete = (e, id, text, label) ->
  return if !id || !text

  $this = $(@)
  if $this.hasClass('anime-suggest')
    type = 'animes'
    url = '/animes/'+id
    bubbled = true

  $container = $this.next().next().children('.container')
  return if $container.find('[value="'+id+'"]').length

  $container.append(
    '<li>' +
      '<span class="item-minus"></span>' +
      '<input type="hidden" name="'+type+'[]" value="'+id+'" />' +
      '<a href="'+url+'" ' +
        (if bubbled then 'class="bubbled" data-remote="true"' else '') +
        '>'+text+'</a>' +
    '</li>'
  )
  process_current_dom() if bubbled
  $this.attr('value', '')
  recalc_animes_count()
  #recalc_duration()

#$(document.body).on 'change', '#contest_votes_per_round, #contest_rounds_interval, #contest_round_duration', ->
  #recalc_duration()

# пересчёт числа аниме
recalc_animes_count = ->
  $('.animes-count').html $('#animes_').next().find('a').length

# пересчёт длительности контеста
#recalc_duration = ->
  #animes = $('#animes_').next().find('a').length
  #votes = parseFloat(fac(animes)) / fac(2) / fac(animes - 2)

  #votes_per_round = parseInt $('#contest_votes_per_round').val()
  #rounds_interval = parseInt $('#contest_vote_interval').val()
  #round_duration = parseInt $('#contest_vote_duration').val()

  #$('#contest_duration_in_days').val(Math.ceil(votes / votes_per_round) * rounds_interval)

#fac = (i) ->
  #if i < 2
    #1
  #else
    #i * fac(i - 1)
