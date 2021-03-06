#= require thresholds/on_thresholds
#= require_tree

# We do the check again so tests don't trigger this initialization
onThresholds -> if $('#thresholds-main').length > 0
  match = window.location.toString().match(/\/collections\/(\d+)\/thresholds/)
  collectionId = parseInt(match[1])

  window.model = new MainViewModel(collectionId)
  ko.applyBindings window.model

  $.get "/collections/#{collectionId}.json", (collection) ->
    window.model.collectionIcon = collection.icon

  $.get "/collections/#{collectionId}/fields.json", (layers) ->
    fields = $.map(layers, (layer) -> layer.fields)
    window.model.compareFields $.map fields, (field) -> new Field field unless field.kind == 'hierarchy' || field.kind == 'user' || field.kind == 'email' || field.kind == 'phone' || field.kind == 'select_many'
    window.model.fields $.map fields, (field) -> new Field field unless field.kind == 'hierarchy' || field.kind == 'user' || field.kind == 'email' || field.kind == 'phone' || field.kind == 'select_many'


    $.get "/plugin/alerts/collections/#{collectionId}/thresholds.json", (thresholds) ->
      thresholds = $.map thresholds, (threshold) -> new Threshold threshold, window.model.collectionIcon
      window.model.thresholds thresholds
      window.model.isReady(true)



