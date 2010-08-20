:- module(compare,
	  [
	   clear_stats/0,
	   clear_nicknames/0,
	   show_alignments/2,
	   show_overlap/2,

	   % misc comparison predicates:
	   map_iterator/1,	   % -Map
	   has_map/3,              % +Map, -Format -Graph
	   find_graphs/2           % +Map, -GraphList

	  ]
	 ).

/** <module> Amalgame compare mapping module

This module compares mappings as they are found by different matchers.
It assumes matchers assert mappings in different name graphs.

@author Jacco van Ossenbruggen
@license GPL
*/

:- use_module(library(assoc)).
:- use_module(library(semweb/rdf_db)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_dispatch)).

:- use_module(components(label)).
:- use_module('../namespaces').





%%	map_iterator(-Map) is non_det.
%
%	Iterates over all maps to be compared. Map is currently of the
%	form [C1, C2], simply meaning there is a mapping from C1 to C2.
%	What other information is available about this mapping depends
%	on the format it is stored in, see has_map/3 for details.
%
%	This is a stub implementation.
%	@tbd make this configurable over a web interface so that we can
%	restrict the source and target vocabulary.

map_iterator([E1,E2]) :-
	has_map([E1, E2], _, _).

%%	has_map(+Map, -Format, -Graph) is non_det.
%
%	Intended to be used to find graphs that contain Map, and in what
%	Format. Map can be stored in the triple store in several
%	formats. We currently support the following formats:
%
%	* edoal: Alignment map format (EDOAL)
%	* skos: SKOS Mapping Relation
%       * dc: dc:replaces
%
%	@see EDOAL: http://alignapi.gforge.inria.fr/edoal.html

has_map([E1, E2], edoal, Graph) :-
	% FIXME: workaround rdf/4 index bug
	rdf(Cell, align:entity1, E1),
	rdf(Cell, align:entity1, E1, Graph),
	rdf(Cell, align:entity2, E2),
	rdf(Cell, align:entity2, E2, Graph).

has_map([E1, E2], skos, Graph) :-
	rdf_has(E1, skos:mappingRelation, E2, RealProp),
	rdf(E1, RealProp, E2, Graph).

has_map([E1, E2], dc, Graph) :-
	rdf_has(E1, dcterms:replaces, E2, RealProp),
	rdf(E1, RealProp, E2, Graph).

%%	find_graphs(+Map, -Graphs) is det.
%
%	Find all Graphs that have a mapping Map.

find_graphs(Map, Graphs) :-
	findall(Graph,
		has_map(Map, _, Graph:_),
		Graphs).

count_alignments(Format, Graph, Count) :-
	findall(Map, has_map(Map, Format, Graph), Graphs),
	length(Graphs, Count),!.

count_alignments(_,_,-1).

find_overlap(ResultsSorted, [cached(true)]) :-
	rdf(_, amalgame:member, _),
	!, % assume overlap stats have been computed already and can be gathered from the RDF
	findall(C:G:E, is_overlap(G,C,E), Results),
	sort(Results, ResultsSorted).
find_overlap(ResultsSorted, [cached(false)]) :-
	findall(Map, map_iterator(Map), AllMaps),
	find_overlaps(AllMaps, [], Overlaps),
	count_overlaps(Overlaps, [], Results),
	sort(Results, ResultsSorted).

is_overlap(G, C, [E1,E2]) :-
	rdf(Overlap, rdf:type, amalgame:'Overlap', amalgame),
	rdf(Overlap, amalgame:count, literal(C), amalgame),
	rdf(Overlap, amalgame:entity1, E1, amalgame),
	rdf(Overlap, amalgame:entity2, E2, amalgame),
	findall(M, rdf(Overlap, amalgame:member, M), G).

find_overlaps([], Doubles, Uniques) :- sort(Doubles, Uniques).
find_overlaps([Map|Tail], Accum, Out) :-
	find_graphs(Map, Graphs),
	find_overlaps(Tail, [Graphs:Map|Accum], Out).

count_overlaps([], Results, Results) :-
	assert_overlaps(Results).
count_overlaps([Graphs:Map|Tail], Accum, Results) :-
	(   selectchk(Count:Graphs:Example, Accum, NewAccum)
	->  true
	;   Count = 0, NewAccum = Accum, Example=Map
	),
	NewCount is Count + 1,
	count_overlaps(Tail, [NewCount:Graphs:Example|NewAccum], Results).

assert_overlaps([]).
assert_overlaps([C:G:E|Tail]) :-
	E = [E1,E2],
	term_hash(G, Hash),
	rdf_equal(amalgame:'', NS),
	format(atom(URI), '~wamalgame_overlap_~w', [NS,Hash]),
	debug(uri, 'URI: ~w', [URI]),
	assert_overlap_members(URI, G),
	rdf_assert(URI, rdf:type, amalgame:'Overlap', amalgame),
	rdf_assert(URI, amalgame:count, literal(C), amalgame),
	rdf_assert(URI, amalgame:entity1, E1, amalgame),
	rdf_assert(URI, amalgame:entity2, E2, amalgame),
	assert_overlaps(Tail).

assert_overlap_members(_URI, []).
assert_overlap_members(URI, [G|T]) :-
	rdf_assert(URI, amalgame:member, G, amalgame),
	assert_overlap_members(URI, T).

clear_stats :-
	rdf_retractall(_, _, _, amalgame).
clear_nicknames :-
	rdf_retractall(_, _, _, amalgame_nicknames).

has_nickname(Graph,Nick) :-
	% work around bug in rdf/4
	% rdf(Graph, amalgame:nickname, literal(Nick), amalgame_nicknames).
	rdf(Graph, amalgame:nickname, literal(Nick)).
nickname(Graph, Nick) :-
	has_nickname(Graph,Nick), !.
nickname(Graph, Nick) :-
	coin_nickname(Graph, Nick),
	rdf_assert(Graph, amalgame:nickname, literal(Nick), amalgame_nicknames).
coin_nickname(_Graph, Nick) :-
	char_type(Nick, alpha),
	\+ has_nickname(_, Nick).

show_graph(Graph, Options) -->
	{
	 member(nick(true), Options),!,
	 nickname(Graph, Nick),
	 http_link_to_id(list_graph, [graph(Graph)], VLink)
	},
	html(a([href(VLink),title(Graph)],[Nick, ' '])).

show_graph(Graph, _Options) -->
	{
	 http_link_to_id(list_graph, [graph(Graph)], VLink)
	},
	html(a([href(VLink)],\turtle_label(Graph))).

show_countlist([], Total) -->
	html(tr([id(finalrow)],
		[td(''),
		 td([style('text-align: right')], Total),
		 td('Total (unique alignments)')
		])).

show_countlist([Count:L:Example|T], Number) -->
	{
	  NewNumber is Number + Count
	},
	html(tr([
		 td(\show_graphs(L, [nick(true)])),
		 td([style('text-align: right')],Count),
		 \show_example(Example)
		])),
	show_countlist(T,NewNumber).

show_example([E1, E2]) -->
	{
	 atom(E1), atom(E2),
	 http_link_to_id(list_resource, [r(E1)], E1Link),
	 http_link_to_id(list_resource, [r(E2)], E2Link)
	},
	html([td(a([href(E1Link)],\turtle_label(E1))),
	      td(a([href(E2Link)],\turtle_label(E2)))]).

show_example([E1, E2]) -->
	html([td(E1),td(E2)]).

show_graphs([],_) --> !.
show_graphs([H|T], Options) -->
	show_graph(H, Options),
	show_graphs(T, Options).

find_alignment_graphs(SortedGraphs, [cached(true)]) :-
	rdf(G, rdf:type, amalgame:'Alignment'), % fix rdf(-+-+)
	rdf(G, rdf:type, amalgame:'Alignment', amalgame),
	!,
	findall(Count:Format:Graph,
		(   rdf(Graph, rdf:type, amalgame:'Alignment'),
		    rdf(Graph, amalgame:format, literal(Format)),
		    rdf(Graph, amalgame:count, literal(Count))
		),
		Graphs
	       ),
	sort(Graphs, SortedGraphs).

find_alignment_graphs(SortedGraphs, [cached(fail)]) :-
	findall(Format:Graph,
		has_map(_, Format,Graph:_),
		DoubleGraphs),
	sort(DoubleGraphs, Graphs),
	findall(Count:Format:Graph,
		(   member(Format:Graph, Graphs),
		    count_alignments(Format, Graph, Count)
		),
		CountedGraphs),
	sort(CountedGraphs, SortedGraphs),
	assert_alignments(SortedGraphs).

assert_alignments([]).
assert_alignments([Count:Format:Graph|Tail]) :-
	rdf_assert(Graph, rdf:type, amalgame:'Alignment',   amalgame),
	rdf_assert(Graph, amalgame:format, literal(Format), amalgame),
	rdf_assert(Graph, amalgame:count,  literal(Count),  amalgame),
	assert_alignments(Tail).

show_alignments -->
	{
	 find_alignment_graphs(Graphs, [cached(Cached)]),
	 (   Cached
	 ->  http_link_to_id(http_clear_cache, [], CacheLink),
	     Note = ['These are cached results, ', a([href(CacheLink)], 'clear cache'), ' to recompute']
	 ;   Note = ''
	 )
	},
	html([div([id(cachenote)], Note),
	      table([id(aligntable)],[tr([
			th('abbrev'),
			th(format),
			th('# maps'),
			th('named graph')
		       ]),
		    \show_alignments(Graphs,0)
		   ])
	     ]).

show_alignments([],Total) -->
	html(tr([id(finalrow)],
		[td(''),
		 td(''),
		 td([style('text-align: right')],Total),
		 td('Total (double counting)')
		])).

show_alignments([Count:Format:Graph|Tail], Number) -->
	{
	  NewNumber is Number + Count
	},
	html(tr([
		 td(\show_graph(Graph, [nick(true)])),
		 td(Format),
		 td([style('text-align: right')],Count),
		 td(\show_graph(Graph, [nick(false)]))
		])),
	show_alignments(Tail, NewNumber).

show_overlap -->
	{
	 find_overlap(CountList, [cached(Cached)]),
	 (   Cached
	 ->  http_link_to_id(http_clear_cache, [], CacheLink),
	     Note = ['These are results from the cache, ', a([href(CacheLink)], 'clear cache'), ' to recompute']
	 ;   Note = ''
	 )
	},
	html([
	      div([id(cachenote)], Note),
	      table([id(aligntable)],
		    [
		     tr([th('Overlap'),th('# maps'), th('Example')]),
		     \show_countlist(CountList,0)
		    ]
		  )
	     ]).









