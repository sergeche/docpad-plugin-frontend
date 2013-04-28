_ = require 'underscore'
fs = require 'fs'

catalogFile = '.build-catalog.json'

catalog = null

getCatalog = () ->
	return catalog if catalog
	if fs.existsSync catalogFile
		try
			catalog = JSON.parse fs.readFileSync catalogFile, 'utf8'
		catch e

	return catalog

# Splits string into array
makeList = (str) ->
	if _.isString str
		return _.compact str.split /\s*,\s*/
	str

# Collects all meta-data for given model, including ancestor
# layouts. This data can be used for further sync lookups
collectMeta = (model, callback) ->
	data = []
	next = (err, ctx) ->
		if err
			return callback err, null

		if ctx
			data.push ctx.getMeta().toJSON()

			if ctx.hasLayout()
				return ctx.getLayout(next)

		callback null, data

	next(null, model)


grabResources = (collection, prefix) ->
	res = {}
	re = new RegExp('^' + prefix + '(\\d+)?$')
	for k, v of collection
		if re.test k
			res[k] = v
	return res


# Collects all resources from document model (transformed document and its layouts)
# with specified prefix
collectResources = (documentModel, prefix) ->
	allMeta = documentModel.get('__allMeta')
	files = []
	if allMeta?
		files = allMeta.map (meta) -> grabResources meta, prefix

	# merge all resource into a singe set
	res = {}
	while r = files.pop()
		_.extend res, r

	# expand all assets
	assets = for k, v of res
		order = -1
		if m = k.match(/(\d+)$/)
			order = parseInt m[1]
		{
			order: order
			files: makeList v
		}

	assets.sort (a, b) ->
		a.order - b.order

	assets = _.flatten assets.map (item) ->
		item.files

	_.uniq _.compact assets


# Export Plugin
module.exports = (BasePlugin) ->
	# Define Plugin
	class FrontendAssetsPlugin extends BasePlugin
		# Plugin name
		name: 'frontend'

		config:
			frontendAssetsOptions:
				# Defines how file cache should be reseted:
				# false – do not reset cache
				# 'date' – reset cache by appending 'date' catalog property to url
				# 'md5' — reset cache by appending 'md5' catalog property to url
				cacheReset: 'date'

				# Method that transforms resource url by inserting cache reset token
				urlTransformer: (url, cacheToken) ->
					return "/#{cacheToken}#{url}" if cacheToken? and url.charAt(0) == '/'
					return url

		generateBefore: (opts, next) ->
			catalog = null
			next()

		renderBefore: (opts, next) ->
			{collection, templateData} = opts
			docs = collection.filter (file) -> file.type == 'document'

			if not docs.length
				return next()

			processedDocs = 0
			errors = 0
			docs.forEach (model) ->
				collectMeta model, (err, meta) ->
					processedDocs++
					if err
						errors++
						return next(err)

					model.set '__allMeta', meta
					if processedDocs >= docs.length
						next()


		extendTemplateData: ({templateData}) ->
			docpad = @docpad
			config = @config.frontendAssetsOptions

			getAssets = (model, prefix) ->
				res = collectResources model, prefix
				cacheToken = config.cacheReset or ''
				isDebug = docpad.getConfig().frontendDebug
				_catalog = getCatalog()

				_.flatten res.map (item) ->
					if item of _catalog
						r = _catalog[item]
						if isDebug
							if r.files.length and _.isString r.files[0]
								# looks like a CSS resources
								# for CSS assets, we don’t have to return dependency list
								# since CSS has native support of resource import (e.g. @import)
								return r.files[0]


							return _.pluck r.files, 'file'

						return config.urlTransformer item, r[cacheToken]

					item

			# list of specified assets: css, js etc
			templateData.assets = (type) ->
				getAssets @documentModel, type

