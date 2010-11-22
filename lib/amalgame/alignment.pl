:-module(ag_alignment,
	 [
	  is_alignment_graph/2,
	  find_graphs/2,
	  nickname/2,
	  split_alignment/4,
	  select_from_alignment/4,

	  align_get_computed_props/2,
	  align_ensure_stats/1,
	  align_clear_stats/1,
	  align_recompute_stats/1,

	  assert_alignment_props/3
	 ]).

:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/rdfs)).
:- use_module(library(semweb/rdf_portray)).

:- use_module(edoal).
:- use_module(map).
:- use_module(opm).

%%	is_alignment_graph(+Graph, ?Format) is semidet.
%       is_alignment_graph(-Graph, ?Format) is nondet.
%
%	Evaluates to true if Graph is an rdf_graph/1 that contains one
%	more alignment mappings for which has_map/3 evaluates to true.
%	@tbd: current implementation assumes all alignments are in one
%	format.

is_alignment_graph(Graph, Format) :-
	ground(Graph),!,
	rdf_graph(Graph),
	graph_format(Graph, Format).

is_alignment_graph(Graph, Format) :-
	var(Graph),
	rdfs_individual_of(Graph, amalgame:'Alignment'),
	rdf_graph(Graph),
	graph_format(Graph, Format).

graph_format(Graph, Format) :-
	rdf(Graph, amalgame:format, literal(Format), amalgame), !.
graph_format(Graph, Format) :-
	(   has_map(_,Format, Graph), !
	->  true
	;   rdfs_individual_of(Graph, amalgame:'Alignment')
	->  Format = empty
	;   fail
	).

%%	find_graphs(+Map, -Graphs) is det.
%
%	Find all Graphs that have a mapping Map.

find_graphs(Map, Graphs) :-
	findall(Graph,
		has_map(Map, _, Graph:_),
		Graphs).


%%	align_get_computed_props(+Graph, -Props) is det.
%
%	Collect all amalgame properties Props of Graph that have been
%	computed already.

align_get_computed_props(Graph, Props) :-
	findall([PropLn, Value],
		(   rdf(Graph, Prop, Value),
		    rdf_global_id(amalgame:PropLn, Prop)
		),
		GraphProps
	       ),
	maplist(=.., Props, GraphProps).

%%	align_ensure_stats(+Type) is det.
%
%	Ensures that alignmets statistics of type Type have been
%	computed. The following types are currently supported:
%
%	* found: makes sure that the algorithm to find all alignment
%	graphs has been run.
%	* totalcount(Graph): idem for total number of alignments in Graph
%	* mapped(Graph): idem for total number of alignments in Graph
%	* source(Graph): idem for the source of the  alignments in Graph
%	* target(Graph): idem for the source of the  alignments in Graph
%	* mapped(Graph): idem for the numbers of mapped source and target concepts in Graph
%

align_ensure_stats(found) :-
	forall(rdf_graph(Graph), classify_graph_type(Graph)).

align_ensure_stats(all(Graph)) :-
	align_ensure_stats(format(Graph)),
	align_ensure_stats(count(Graph)),
	align_ensure_stats(source(Graph)),
	align_ensure_stats(target(Graph)),
	align_ensure_stats(mapped(Graph)).

align_ensure_stats(format(Graph)) :-
	rdf(Graph, amalgame:format, _, amalgame), !.
align_ensure_stats(format(Graph)) :-
	(   has_map(_,Format, Graph:_)
	->  true
	;   Format = empty
	),
	!,
	assert_alignment_props([Graph:[format(literal(Format))]], amalgame),!.
align_ensure_stats(format(_)) :- !.


align_ensure_stats(count(Graph)) :-
	(   rdf(Graph, amalgame:count, _, amalgame)
	->  true
	;   is_alignment_graph(Graph, Format),!,
	    count_alignment(Graph, Format, Count),
	    assert_alignment_props(Graph:[count(literal(type('http://www.w3.org/2001/XMLSchema#int',Count)))], amalgame)
	),!.

align_ensure_stats(source(Graph)) :-
	(   rdf(Graph, amalgame:source, _, amalgame)
	->  true
	;   is_alignment_graph(Graph, Format),!,
	    find_source(Graph, Format, Source),
	    assert_alignment_props(Graph:[source(Source)], amalgame)
	),!.

align_ensure_stats(target(Graph)) :-
	(   rdf(Graph, amalgame:target, _, amalgame)
	->  true
	;   is_alignment_graph(Graph, Format),!,
	    find_target(Graph, Format, Target),
	    assert_alignment_props(Graph:[target(Target)], amalgame)
	),!.


align_ensure_stats(mapped(Graph)) :-
	(   rdf(Graph, amalgame:mappedSourceConcepts, _, amalgame)
	->  true
	;   is_alignment_graph(Graph, Format),!,
	    findall(M1, has_map([M1, _], Format, Graph), M1s),
	    findall(M2, has_map([_, M2], Format, Graph), M2s),
	    sort(M1s, MappedSourceConcepts),
	    sort(M2s, MappedTargetConcepts),
	    length(MappedSourceConcepts, NrMappedSourceConcepts),
	    length(MappedTargetConcepts, NrMappedTargetConcepts),
	    assert_alignment_props(Graph:[mappedSourceConcepts(literal(type('http://www.w3.org/2001/XMLSchema#int', NrMappedSourceConcepts))),
					  mappedTargetConcepts(literal(type('http://www.w3.org/2001/XMLSchema#int', NrMappedTargetConcepts)))
					 ], amalgame)
	),!.

%%	align_clear_stats(+Type) is det.
%%	align_clear_stats(-Type) is nondet.
%
%	Clears all results that have been cached after running
%	ensure_stats(Type).

align_clear_stats(all) :-
	print_message(informational, map(cleared, statistics, 1, amalgame)),
	(   rdf_graph(amalgame)
	->  rdf_unload(amalgame)
	;   true
	),
	print_message(informational, map(cleared, nicknames, 1, amalgame)),
	(   rdf_graph(amalgame_nicknames)
	->  rdf_unload(amalgame_nicknames)
	;   true
	).



align_clear_stats(found) :-
	rdf_retractall(_, rdf:type, amalgame:'Alignment', amalgame),
	rdf_retractall(_, amalgame:format, _, amalgame).

align_clear_stats(nicknames) :-
	rdf_retractall(_, _, _, amalgame_nicknames).

align_clear_stats(graph(Graph)) :-
	rdf_retractall(Graph, _,_,amalgame),
	rdf_retractall(Graph, _,_,amalgame).


%%	align_recompute_stats(+Type) is det.
%%	align_recompute_stats(-Type) is nondet.
%
%	Clears and recomputes statistics of type Type. See
%	ensure_stats/1 for a list of supported types.

align_recompute_stats(Type) :-
	align_clear_stats(Type),
	align_ensure_stats(Type).


count_alignment(Graph, Format, Count) :-
	findall(Map, has_map(Map, Format, Graph), Graphs),
	length(Graphs, Count),
	print_message(informational, map(found, maps, Graph, Count)),
	!.

find_source(Graph, edoal, Source) :-
	rdf(_, align:onto1, Source, Graph),
	rdf_is_resource(Source),
	!.

find_source(Graph, Format, Source) :-
	has_map([E1, _], Format, Graph),!,
	(   rdf_has(E1, skos:inScheme, Source)
	->  true
	;   iri_xml_namespace(E1, Source)
	).
find_source(_, _, null).

find_target(Graph, edoal, Target) :-
	rdf(_, align:onto2, Target, Graph),
	rdf_is_resource(Target),
	!.

find_target(Graph, Format, Target) :-
	has_map([_, E2], Format, Graph), !,
	(   rdf_has(E2, skos:inScheme, Target)
	->  true
	;   iri_xml_namespace(E2, Target)
	).
find_target(_, _, null).

assert_alignment_props(Alignment, Props, Graph) :-
	assert_alignment_props(Alignment:Props, Graph).

assert_alignment_props([],_).
assert_alignment_props([Head|Tail], Graph) :-
	assert_alignment_props(Head, Graph),
	assert_alignment_props(Tail, Graph),!.

assert_alignment_props(Alignment:Props, Graph) :-
	(   rdfs_individual_of(Alignment, amalgame:'Alignment')
	->  true
	;   rdf_assert(Alignment, rdf:type, amalgame:'LoadedAlignment',	Graph)
	),
	rdf_equal(amalgame:'', NS),
	forall(member(M,Props),
	       (   M =.. [PropName, Value],
		   format(atom(URI), '~w~w', [NS,PropName]),
		   rdf_assert(Alignment, URI, Value, Graph)
	       )).

has_nickname(Graph,Nick) :-
	rdf(Graph, amalgame:nickname, literal(Nick), amalgame_nicknames).
nickname(Graph, Nick) :-
	has_nickname(Graph,Nick), !.
nickname(Graph, Nick) :-
	coin_nickname(Graph, Nick),
	rdf_assert(Graph, amalgame:nickname, literal(Nick), amalgame_nicknames).
coin_nickname(_Graph, Nick) :-
	char_type(Nick, alpha),
	\+ has_nickname(_, Nick),!.

split_alignment(Request, SourceGraph, Condition, SplittedGraphs) :-
	has_map(_,Format,SourceGraph),!,
	findall(Map:Options, has_map(Map, Format, Options, SourceGraph), Maps),
	reassert(Request, Maps, SourceGraph, Condition, [], SplittedGraphs).

select_from_alignment(Request, SourceGraph, Condition, TargetGraph) :-
	findall([C1,C2,MapProps], has_map([C1,C2], _, MapProps, SourceGraph), Maps),
	forall(member([C1,C2,MapProps], Maps),
	       (   meets_condition(Condition, C1,C2, MapProps, SourceGraph)
	       ->  assert_cell(C1, C2, [graph(TargetGraph)|MapProps])
	       ;   true
	       )
	      ),
	(   rdf_graph(TargetGraph)
	->  rdf_assert(TargetGraph, rdf:type, amalgame:'SelectionAlignment', TargetGraph),
	    rdf_bnode(Process),
	    rdf_assert(Process, rdfs:label, literal('Amalgame mapping filter'), TargetGraph),
	    rdf_assert(Process, amalgame:condition, literal(Condition), TargetGraph),
	    opm_was_generated_by(Process, TargetGraph, TargetGraph,
				 [was_derived_from([SourceGraph]),
				  request(Request)
				 ])
	;   true
	).

meets_condition(one_to_one, C1, C2, _MapOptions, Graph) :-
	has_map([C1, C2], _, Graph),
	\+ ((has_map([A1, C2], _, Graph), A1 \= C1);
	    (has_map([C1, A2], _, Graph), A2 \= C2)
	   ).
meets_condition(unique_label, _C1, _C2, MapOptions, _Graph) :-
	option(method(Method), MapOptions),
	sub_atom(Method, _, _, _, 'exact 1/1 ').

reassert(_, [], _ , _, Graphs, Graphs).
reassert(Request, [Map:Options|Tail], OldGraph, Condition, Accum, Results) :-
	target_graph(Map, OldGraph, Condition, NewGraph),
	(   memberchk(NewGraph, Accum)
	->  NewAccum = Accum
	;   NewAccum = [NewGraph|Accum],
	    (	rdf_graph(NewGraph) -> rdf_unload(NewGraph); true),

	    rdf_assert(NewGraph, rdf:type, amalgame:'PartitionedAlignment', NewGraph),
	    rdf_assert(OldGraph, void:subset, NewGraph, NewGraph),

	    rdf_bnode(Process),
	    rdf_assert(Process, rdfs:label, literal('Amalgame split operation'), NewGraph),
	    rdf_assert(Process, amalgame:condition, literal(Condition), NewGraph),
	    opm_was_generated_by(Process, NewGraph, NewGraph,
				 [was_derived_from([OldGraph]),
				  request(Request)
				 ])
	),
	Map = [E1,E2],
	assert_cell(E1, E2, [graph(NewGraph), Options]),
	reassert(Request, Tail, OldGraph, Condition, NewAccum, Results).

target_graph([E1, E2], OldGraph, Condition, Graph) :-
	(   Condition = sourceType
	->  findall(Type, rdf(E1, rdf:type, Type), Types)
	;   findall(Type, rdf(E2, rdf:type, Type), Types)
	),
	sort(Types, STypes),
	rdf_equal(skos:'Concept', SkosConcept),
	(   selectchk(SkosConcept, STypes, GTypes)
	->  true
	;   GTypes = STypes
	),
	(   GTypes = [FirstType|_]
	->  format(atom(Graph), '~p_~p', [OldGraph, FirstType])
	;   Graph = OldGraph
	).

classify_graph_type(Graph) :-
	rdfs_individual_of(Graph, amalgame:'Alignment'), !.

classify_graph_type(Graph) :-
	rdfs_individual_of(Graph, amalgame:'NoAlignmentGraph'), !.

classify_graph_type(Graph) :-
	has_map(_, Format, Graph),!,
	rdf_assert(Graph, rdf:type, amalgame:'LoadedAlignment', amalgame),
	rdf_assert(Graph, amalgame:format, literal(Format), amalgame).

classify_graph_type(Graph) :-
	rdf_assert(Graph, rdf:type, amalgame:'NoAlignmentGraph', amalgame).