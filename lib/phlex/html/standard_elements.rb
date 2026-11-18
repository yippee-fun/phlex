# frozen_string_literal: true

# Standard HTML elements accept content and always have a closing tag.
module Phlex::HTML::StandardElements
	extend Phlex::SGML::Elements

	# Outputs an `<a>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/a)
	# [Spec](https://html.spec.whatwg.org/#the-a-element)
	register_element def a(**attributes, &content) = nil

	# Outputs an `<abbr>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/abbr)
	# [Spec](https://html.spec.whatwg.org/#the-abbr-element)
	register_element def abbr(**attributes, &content) = nil

	# Outputs an `<address>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/address)
	# [Spec](https://html.spec.whatwg.org/#the-address-element)
	register_element def address(**attributes, &content) = nil

	# Outputs an `<article>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/article)
	# [Spec](https://html.spec.whatwg.org/#the-article-element)
	register_element def article(**attributes, &content) = nil

	# Outputs an `<aside>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/aside)
	# [Spec](https://html.spec.whatwg.org/#the-aside-element)
	register_element def aside(**attributes, &content) = nil

	# Outputs an `<audio>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/audio)
	# [Spec](https://html.spec.whatwg.org/#the-audio-element)
	# [Can I Use?](https://caniuse.com/audio)
	register_element def audio(**attributes, &content) = nil

	# Outputs a `<b>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/b)
	# [Spec](https://html.spec.whatwg.org/#the-b-element)
	register_element def b(**attributes, &content) = nil

	# Outputs a `<bdi>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/bdi)
	# [Spec](https://html.spec.whatwg.org/#the-bdi-element)
	register_element def bdi(**attributes, &content) = nil

	# Outputs a `<bdo>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/bdo)
	# [Spec](https://html.spec.whatwg.org/#the-bdo-element)
	register_element def bdo(**attributes, &content) = nil

	# Outputs a `<blockquote>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/blockquote)
	# [Spec](https://html.spec.whatwg.org/#the-blockquote-element)
	register_element def blockquote(**attributes, &content) = nil

	# Outputs a `<body>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/body)
	# [Spec](https://html.spec.whatwg.org/#the-body-element)
	register_element def body(**attributes, &content) = nil

	# Outputs a `<button>` tag.
	# The `<button>` element is an interactive element activated by a user with a mouse, keyboard, finger, voice command, or other assistive technology to perform an action, such as submitting a form or opening a dialog.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/button)
	# [Spec](https://html.spec.whatwg.org/#the-button-element)
	register_element def button(**attributes, &content) = nil

	# Outputs a `<canvas>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/canvas)
	# [Spec](https://html.spec.whatwg.org/#the-canvas-element)
	register_element def canvas(**attributes, &content) = nil

	# Outputs a `<caption>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/caption)
	# [Spec](https://html.spec.whatwg.org/#the-caption-element)
	register_element def caption(**attributes, &content) = nil

	# Outputs a `<cite>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/cite)
	# [Spec](https://html.spec.whatwg.org/#the-cite-element)
	register_element def cite(**attributes, &content) = nil

	# Outputs a `<code>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/code)
	# [Spec](https://html.spec.whatwg.org/#the-code-element)
	register_element def code(**attributes, &content) = nil

	# Outputs a `<colgroup>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/colgroup)
	# [Spec](https://html.spec.whatwg.org/#the-colgroup-element)
	register_element def colgroup(**attributes, &content) = nil

	# Outputs a `<data>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/data)
	# [Spec](https://html.spec.whatwg.org/#the-data-element)
	register_element def data(**attributes, &content) = nil

	# Outputs a `<datalist>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/datalist)
	# [Spec](https://html.spec.whatwg.org/#the-datalist-element)
	register_element def datalist(**attributes, &content) = nil

	# Outputs a `<dd>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/dd)
	# [Spec](https://html.spec.whatwg.org/#the-dd-element)
	register_element def dd(**attributes, &content) = nil

	# Outputs a `<del>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/del)
	# [Spec](https://html.spec.whatwg.org/#the-del-element)
	register_element def del(**attributes, &content) = nil

	# Outputs a `<details>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/details)
	# [Spec](https://html.spec.whatwg.org/#the-details-element)
	# [Can I Use?](https://caniuse.com/details)
	register_element def details(**attributes, &content) = nil

	# Outputs a `<dfn>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/dfn)
	# [Spec](https://html.spec.whatwg.org/#the-dfn-element)
	register_element def dfn(**attributes, &content) = nil

	# Outputs a `<dialog>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/dialog)
	# [Spec](https://html.spec.whatwg.org/#the-dialog-element)
	# [Can I use?](https://caniuse.com/dialog)
	register_element def dialog(**attributes, &content) = nil

	# Outputs a `<div>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/div)
	# [Spec](https://html.spec.whatwg.org/#the-div-element)
	register_element def div(**attributes, &content) = nil

	# Outputs a `<dl>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/dl)
	# [Spec](https://html.spec.whatwg.org/#the-dl-element)
	register_element def dl(**attributes, &content) = nil

	# Outputs a `<dt>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/dt)
	# [Spec](https://html.spec.whatwg.org/#the-dt-element)
	register_element def dt(**attributes, &content) = nil

	# Outputs an `<em>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/em)
	# [Spec](https://html.spec.whatwg.org/#the-em-element)
	register_element def em(**attributes, &content) = nil

	# [EXPERIMENTAL] Outputs a `<fencedframe>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/fencedframe)
	# [Can I Use?](https://caniuse.com/mdn-html_elements_fencedframe)
	register_element def fencedframe(**attributes, &content) = nil

	# Outputs a `<fieldset>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/fieldset)
	# [Spec](https://html.spec.whatwg.org/#the-fieldset-element)
	register_element def fieldset(**attributes, &content) = nil

	# Outputs a `<figcaption>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/figcaption)
	# [Spec](https://html.spec.whatwg.org/#the-figcaption-element)
	register_element def figcaption(**attributes, &content) = nil

	# Outputs a `<figure>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/figure)
	# [Spec](https://html.spec.whatwg.org/#the-figure-element)
	register_element def figure(**attributes, &content) = nil

	# Outputs a `<footer>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/footer)
	# [Spec](https://html.spec.whatwg.org/#the-footer-element)
	register_element def footer(**attributes, &content) = nil

	# Outputs a `<form>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/form)
	# [Spec](https://html.spec.whatwg.org/#the-form-element)
	register_element def form(**attributes, &content) = nil

	# Outputs an `<h1>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/h1)
	# [Spec](https://html.spec.whatwg.org/#the-h1-element)
	register_element def h1(**attributes, &content) = nil

	# Outputs an `<h2>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/h2)
	# [Spec](https://html.spec.whatwg.org/#the-h2-element)
	register_element def h2(**attributes, &content) = nil

	# Outputs an `<h3>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/h3)
	# [Spec](https://html.spec.whatwg.org/#the-h3-element)
	register_element def h3(**attributes, &content) = nil

	# Outputs an `<h4>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/h4)
	# [Spec](https://html.spec.whatwg.org/#the-h4-element)
	register_element def h4(**attributes, &content) = nil

	# Outputs an `<h5>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/h5)
	# [Spec](https://html.spec.whatwg.org/#the-h5-element)
	register_element def h5(**attributes, &content) = nil

	# Outputs an `<h6>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/h6)
	# [Spec](https://html.spec.whatwg.org/#the-h6-element)
	register_element def h6(**attributes, &content) = nil

	# Outputs a `<head>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/head)
	# [Spec](https://html.spec.whatwg.org/#the-head-element)
	register_element def head(**attributes, &content) = nil

	# Outputs a `<header>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/header)
	# [Spec](https://html.spec.whatwg.org/#the-header-element)
	register_element def header(**attributes, &content) = nil

	# Outputs an `<hgroup>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/hgroup)
	# [Spec](https://html.spec.whatwg.org/#the-hgroup-element)
	register_element def hgroup(**attributes, &content) = nil

	# Outputs an `<html>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/html)
	# [Spec](https://html.spec.whatwg.org/#the-html-element)
	register_element def html(**attributes, &content) = nil

	# Outputs an `<i>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/i)
	# [Spec](https://html.spec.whatwg.org/#the-i-element)
	register_element def i(**attributes, &content) = nil

	# Outputs an `<iframe>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/iframe)
	# [Spec](https://html.spec.whatwg.org/#the-iframe-element)
	register_element def iframe(**attributes, &content) = nil

	# Outputs an `<ins>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/ins)
	# [Spec](https://html.spec.whatwg.org/#the-ins-element)
	register_element def ins(**attributes, &content) = nil

	# Outputs a `<kbd>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/kbd)
	# [Spec](https://html.spec.whatwg.org/#the-kbd-element)
	register_element def kbd(**attributes, &content) = nil

	# Outputs a `<label>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/label)
	# [Spec](https://html.spec.whatwg.org/#the-label-element)
	register_element def label(**attributes, &content) = nil

	# Outputs a `<legend>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/legend)
	# [Spec](https://html.spec.whatwg.org/#the-legend-element)
	register_element def legend(**attributes, &content) = nil

	# Outputs a `<li>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/li)
	# [Spec](https://html.spec.whatwg.org/#the-li-element)
	register_element def li(**attributes, &content) = nil

	# Outputs a `<main>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/main)
	# [Spec](https://html.spec.whatwg.org/#the-main-element)
	register_element def main(**attributes, &content) = nil

	# Outputs a `<map>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/map)
	# [Spec](https://html.spec.whatwg.org/#the-map-element)
	register_element def map(**attributes, &content) = nil

	# Outputs a `<mark>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/mark)
	# [Spec](https://html.spec.whatwg.org/#the-mark-element)
	register_element def mark(**attributes, &content) = nil

	# Outputs a `<menu>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/menu)
	# [Spec](https://html.spec.whatwg.org/#the-menu-element)
	register_element def menu(**attributes, &content) = nil

	# Outputs a `<meter>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/meter)
	# [Spec](https://html.spec.whatwg.org/#the-meter-element)
	register_element def meter(**attributes, &content) = nil

	# Outputs a `<nav>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/nav)
	# [Spec](https://html.spec.whatwg.org/#the-nav-element)
	register_element def nav(**attributes, &content) = nil

	# Outputs a `<noscript>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/noscript)
	# [Spec](https://html.spec.whatwg.org/#the-noscript-element)
	register_element def noscript(**attributes, &content) = nil

	# Outputs an `<object>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/object)
	# [Spec](https://html.spec.whatwg.org/#the-object-element)
	register_element def object(**attributes, &content) = nil

	# Outputs an `<ol>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/ol)
	# [Spec](https://html.spec.whatwg.org/#the-ol-element)
	register_element def ol(**attributes, &content) = nil

	# Outputs an `<optgroup>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/optgroup)
	# [Spec](https://html.spec.whatwg.org/#the-optgroup-element)
	register_element def optgroup(**attributes, &content) = nil

	# Outputs an `<option>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/option)
	# [Spec](https://html.spec.whatwg.org/#the-option-element)
	register_element def option(**attributes, &content) = nil

	# Outputs an `<output>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/output)
	# [Spec](https://html.spec.whatwg.org/#the-output-element)
	register_element def output(**attributes, &content) = nil

	# Outputs a `<p>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/p)
	# [Spec](https://html.spec.whatwg.org/#the-p-element)
	register_element def p(**attributes, &content) = nil

	# Outputs a `<picture>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/picture)
	# [Spec](https://html.spec.whatwg.org/#the-picture-element)
	# [Can I Use?](https://caniuse.com/picture)
	register_element def picture(**attributes, &content) = nil

	# Outputs a `<pre>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/pre)
	# [Spec](https://html.spec.whatwg.org/#the-pre-element)
	register_element def pre(**attributes, &content) = nil

	# Outputs a `<progress>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/progress)
	# [Spec](https://html.spec.whatwg.org/#the-progress-element)
	register_element def progress(**attributes, &content) = nil

	# Outputs a `<q>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/q)
	# [Spec](https://html.spec.whatwg.org/#the-q-element)
	register_element def q(**attributes, &content) = nil

	# Outputs an `<rp>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/rp)
	# [Spec](https://html.spec.whatwg.org/#the-rp-element)
	register_element def rp(**attributes, &content) = nil

	# Outputs an `<rt>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/rt)
	# [Spec](https://html.spec.whatwg.org/#the-rt-element)
	register_element def rt(**attributes, &content) = nil

	# Outputs a `<ruby>` tag. (The best tag ever!)
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/ruby)
	# [Spec](https://html.spec.whatwg.org/#the-ruby-element)
	register_element def ruby(**attributes, &content) = nil

	# Outputs an `<s>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/s)
	# [Spec](https://html.spec.whatwg.org/#the-s-element)
	register_element def s(**attributes, &content) = nil

	# Outputs a `<samp>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/samp)
	# [Spec](https://html.spec.whatwg.org/#the-samp-element)
	register_element def samp(**attributes, &content) = nil

	# Outputs a `<script>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/script)
	# [Spec](https://html.spec.whatwg.org/#the-script-element)
	register_element def script(**attributes, &content) = nil

	# Outputs a `<search>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/search)
	# [Spec](https://html.spec.whatwg.org/#the-search-element)
	# [Can I Use?](https://caniuse.com/mdn-html_elements_search)
	register_element def search(**attributes, &content) = nil

	# Outputs a `<section>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/section)
	# [Spec](https://html.spec.whatwg.org/#the-section-element)
	register_element def section(**attributes, &content) = nil

	# Outputs a `<select>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/select)
	# [Spec](https://html.spec.whatwg.org/#the-select-element)
	register_element def select(**attributes, &content) = nil

	# [EXPERIMENTAL] Outputs a `<selectedcontent>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/selectedcontent)
	# [Draft Spec](https://github.com/whatwg/html/pull/10633)
	# [Can I Use?](https://caniuse.com/mdn-html_elements_selectedcontent)
	register_element def selectedcontent(**attributes, &content) = nil

	# Outputs a `<slot>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/slot)
	# [Spec](https://html.spec.whatwg.org/#the-slot-element)
	register_element def slot(**attributes, &content) = nil

	# Outputs a `<small>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/small)
	# [Spec](https://html.spec.whatwg.org/#the-small-element)
	register_element def small(**attributes, &content) = nil

	# Outputs a `<span>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/span)
	# [Spec](https://html.spec.whatwg.org/#the-span-element)
	register_element def span(**attributes, &content) = nil

	# Outputs a `<strong>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/strong)
	# [Spec](https://html.spec.whatwg.org/#the-strong-element)
	register_element def strong(**attributes, &content) = nil

	# Outputs a `<style>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/style)
	# [Spec](https://html.spec.whatwg.org/#the-style-element)
	register_element def style(**attributes, &content) = nil

	# Outputs a `<sub>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/sub)
	# [Spec](https://html.spec.whatwg.org/#the-sub-element)
	register_element def sub(**attributes, &content) = nil

	# Outputs a `<summary>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/summary)
	# [Spec](https://html.spec.whatwg.org/#the-summary-element)
	# [Can I Use?](https://caniuse.com/details)
	register_element def summary(**attributes, &content) = nil

	# Outputs a `<sup>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/sup)
	# [Spec](https://html.spec.whatwg.org/#the-sup-element)
	register_element def sup(**attributes, &content) = nil

	# Outputs an `<svg>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/SVG/Element/svg)
	# [Spec](https://html.spec.whatwg.org/#the-svg-element)
	register_element def svg(**attributes, &content) = nil

	# Outputs a `<table>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/table)
	# [Spec](https://html.spec.whatwg.org/#the-table-element)
	register_element def table(**attributes, &content) = nil

	# Outputs a `<tbody>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/tbody)
	# [Spec](https://html.spec.whatwg.org/#the-tbody-element)
	register_element def tbody(**attributes, &content) = nil

	# Outputs a `<td>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/td)
	# [Spec](https://html.spec.whatwg.org/#the-td-element)
	register_element def td(**attributes, &content) = nil

	# Outputs a `<template>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/template)
	# [Spec](https://html.spec.whatwg.org/#the-template-element)
	register_element def template(**attributes, &content) = nil

	# Outputs a `<textarea>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/textarea)
	# [Spec](https://html.spec.whatwg.org/#the-textarea-element)
	register_element def textarea(**attributes, &content) = nil

	# Outputs a `<tfoot>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/tfoot)
	# [Spec](https://html.spec.whatwg.org/#the-tfoot-element)
	register_element def tfoot(**attributes, &content) = nil

	# Outputs a `<th>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/th)
	# [Spec](https://html.spec.whatwg.org/#the-th-element)
	register_element def th(**attributes, &content) = nil

	# Outputs a `<thead>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/thead)
	# [Spec](https://html.spec.whatwg.org/#the-thead-element)
	register_element def thead(**attributes, &content) = nil

	# Outputs a `<time>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/time)
	# [Spec](https://html.spec.whatwg.org/#the-time-element)
	register_element def time(**attributes, &content) = nil

	# Outputs a `<title>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/title)
	# [Spec](https://html.spec.whatwg.org/#the-title-element)
	register_element def title(**attributes, &content) = nil

	# Outputs a `<tr>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/tr)
	# [Spec](https://html.spec.whatwg.org/#the-tr-element)
	register_element def tr(**attributes, &content) = nil

	# Outputs a `<u>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/u)
	# [Spec](https://html.spec.whatwg.org/#the-u-element)
	register_element def u(**attributes, &content) = nil

	# Outputs a `<ul>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/ul)
	# [Spec](https://html.spec.whatwg.org/#the-ul-element)
	register_element def ul(**attributes, &content) = nil

	# Outputs a `<var>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/var)
	# [Spec](https://html.spec.whatwg.org/#the-var-element)
	register_element def var(**attributes, &content) = nil

	# Outputs a `<video>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/video)
	# [Spec](https://html.spec.whatwg.org/#the-video-element)
	# [Can I Use?](https://caniuse.com/video)
	register_element def video(**attributes, &content) = nil

	# Outputs a `<wbr>` tag.
	#
	# [MDN Docs](https://developer.mozilla.org/docs/Web/HTML/Element/wbr)
	# [Spec](https://html.spec.whatwg.org/#the-wbr-element)
	register_element def wbr(**attributes, &content) = nil
end
