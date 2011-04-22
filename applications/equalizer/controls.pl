:- module(eq_controls,
	  [ html_controls//0
	  ]).

:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_json)).
:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/rdf_label)).
:- use_module(library(amalgame/amalgame_modules)).

:- use_module(opmviz).
:- use_module(eq_util).

:- http_handler(amalgame(data/addprocess), http_add_process, []).

http_add_process(Request) :-
	http_parameters(Request,
			[ input(Input,
				[uri,
				 optional(true),
				 description('URI of input mapping')]),
			  source(Source,
				 [uri,
				  optional(true),
				  description('URI of the source')]),
			  target(Target,
				 [uri,
				  optional(true),
				  description('URI of the target')]),
			  process(ProcessType,
				  [uri,
				   description('URI of the process class')]),
			  alignment(Alignment,
				    [uri,
				     description('URI of the alignment graph to which the process is added')])
			],
			[form_data(Params0)]),
	(   ((nonvar(Source), nonvar(Target)) ; nonvar(Input))
	->  rdf_bnode(ProcessURI),
	    subtract(Params0, [input=_,source=_,target=_,process=_], Params),
	    rdf_transaction((
			     assert_process(ProcessURI, ProcessType, Alignment, Params),
			     assert_input(ProcessURI, Alignment, Source, Target, Input)))
	),
	js_alignment_nodes(Alignment, Nodes),
	reply_json(json([nodes=json(Nodes)])).

assert_input(Process, Graph, Source, Target, _Input) :-
 	nonvar(Source),
	nonvar(Target),
	!,
	rdf_assert(Process, amalgame:source, Source, Graph),
	rdf_assert(Process, amalgame:target, Target, Graph).
assert_input(Process, Graph, _Source, _Target, Input) :-
 	rdf_assert(Process, amalgame:input, Input, Graph).

assert_process(ProcessURI, ProcessType, Graph, Params) :-
 	rdf_bnode(OutputURI),
	process_label(ProcessType, ProcessLabel),
	uri_query_components(Search, Params),
 	rdf_assert(ProcessURI, rdf:type, ProcessType, Graph),
	rdf_assert(ProcessURI, rdfs:label, ProcessLabel, Graph),
	rdf_assert(ProcessURI, amalgame:parameters, Search, Graph),
	rdf_assert(OutputURI, rdf:type, amalgame:'Mapping', Graph),
        rdf_assert(OutputURI, opmv:wasGeneratedBy, ProcessURI, Graph).

process_label(P, Lit) :-
	(   rdf_label(P, L)
	->  Lit = L
	;   rdf_global_id(_:Local, P),
	    Lit = literal(Local)
	).


html_controls -->
	{ amalgame_class_modules(amalgame:'Matcher', Matchers),
 	  amalgame_class_modules(amalgame:'Selecter', Selecters)
	},

 	html(div([class('yui3-accordion')],
		  [ \html_accordion_item(infobox, 'Info', info, false, []),
		    \html_accordion_item(align, 'Align', vocab, true,
			    [\html_align_select,
			     \html_tab_view(Matchers)
			    ]),
		    \html_accordion_item(merge, 'Merge', vocab, true, []),
		    \html_accordion_item(filter, 'Filter', mapping, true,
					 \html_tab_view(Matchers)),
		    \html_accordion_item(partition, 'Partition', mapping, true,
					 \html_tab_view(Selecters))
		  ])
	     ).

html_align_select -->
	html(table([tr([td(input([type(button), id(sourcebtn), disabled(true), value('set as source')])),
			td(input([type(text), disabled(true), id(source), name(source), size(40), autocomplete(off)]))
		       ]),
		    tr([td(input([type(button), id(targetbtn), disabled(true), value('set as target')])),
			td(input([type(text), disabled(true), id(target), name(target), size(40), autocomplete(off)]))
		       ])
		   ])).

%%	html_accordion_item(+Id, +Label, +CSSClass, +Disabled +Body)
%
%	Emit YUI3 node accordion html markup.

html_accordion_item(Id, Label, Class, Disabled, Body) -->
	{ (   Disabled
	  ->  D = disabled
	  ;   D = ''
	  )
	},
	html(div([id(Id), class('yui3-accordion-item '+Class)],
		 [ div(class('yui3-accordion-item-hd'),
		       a([href('javascript:void(0)'),
			  class('yui3-accordion-item-trigger')],
			 Label)),
		   div(class('yui3-accordion-item-bd '+D),
		       Body)
		 ])).

%%	html_tab_view(+Modules)
%
%	Emit YUI3 tabview html markup.
%
html_tab_view(Modules) -->
	html(div(class('yui3-tabview'),
		 [ ul(\html_tab_list(Modules)),
		   div(\html_tab_panel(Modules))
		 ])).

html_tab_list([]) --> !.
html_tab_list([URI-Module|Ms]) -->
	{ module_label(URI, Label)
	},
	html(li(a([href('#'+Module)], Label))),
	html_tab_list(Ms).

module_label(M, Label) :-
	rdf_label(M, Lit),
	!,
	literal_text(Lit, Label).
module_label(M, Label) :-
	rdf_global_id(_:Label, M).

html_tab_panel([]) --> !.
html_tab_panel([URI-Module|Ms]) -->
	{ amalgame_module_parameters(Module, Params)
	},
	html(form(id(URI),
		[ table(tbody(\html_parameter_form(Params))),
		  div(class('control-buttons'),
		      input([type(button), disabled(true), class('control-submit'), value('Go')]))
		])),
	html_tab_panel(Ms).

%%	html_module_parameters(+ParameterList)
%
%	Emit html form components corresponding to Parameters.

html_parameter_form([]) --> !.
html_parameter_form([parameter(Name, Type, Default, Desc)|Ps]) -->
 	html(tr(title(Desc),
		 [td(label(Name)),
		  td(\input_value(Type, Default, Name))
		  ])),
	html_parameter_form(Ps).


%%	input_value(+Type, +Value, +Name)// is det.
%
%	Emit an form-field for Value.

:- multifile
	input_item/5.	       % input_item(+Type, +Value, +Name)//

input_value(Type, Value, Name) -->
 	(   input_item(Type, Value, Name)
	->  []
	;   builtin_input_item(Type, Value, Name)
	).

builtin_input_item(boolean, Value, Name) --> !,
	builtin_input_item(oneof([true,false]), Value, Name).
builtin_input_item(between(L,U), Value, Name) --> !,
	html(input([ type(range),
		     name(Name),
		     disabled(true),
		     min(L), max(U), value(Value)
		   ])).
builtin_input_item(oneof(List), Value, Name) --> !,
	html(select([name(Name), disabled(true)], \oneof(List, Value))).
builtin_input_item(atom, Value, Name) --> !,
	html(input([name(Name), size(40), disabled(true), value(Value)])).
builtin_input_item(_, Value, Name) -->
	{ format(string(S), '~q', [Value])
	},
	html(input([name(Name), size(40), disabled(true), value(S)])).

oneof([], _) -->
	[].
oneof([H|T], Value) -->
	(   {H == Value}
	->  html([ option([selected(selected),value(H)], H) ])
	;   html([ option([                   value(H)], H) ])
	),
	oneof(T, Value).

