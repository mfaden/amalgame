:- module(am_skosvocs,
          [
	   skos_label/2,
	   skos_label/3,
	   voc_get_computed_props/2,
	   voc_clear_stats/0,
	   voc_ensure_stats/1,
	   voc_partition/2,
	   voc_delpart/0
          ]).

:- use_module(library(http/http_dispatch)).
:- use_module(library(http/html_write)).

:- use_module(library(semweb/rdfs)).
:- use_module(library(semweb/rdf_db)).


:- use_module(amalgame(mappings/map)).

/** <module> Compute and store vocabulary-oriented statistics as RDF.

Currently supported statistical properties include:
* numberOfConcepts(xsd:int)
* numberOfPrefLabels(xsd:int)
* numberOfAltLabels(xsd:int)
* numberOfMappedConcepts(xsd:int)

Side effect: These statistics will also be asserted as RDF
triples to the 'amalgame_vocs' named graph, using similarly named
properties with the 'amalgame:' namespace prefix. These asserted
triples will be used in subsequent calls for efficiency reasons.

See also http_clear_cache/1.

@author Jacco van Ossenbruggen
*/

%%	voc_get_computed_props(+Voc, -Props) is det.
%
%	Collect all amalgame properties Props of Voc that have been
%	already computed and asserted in the amalgame named graph.
%

voc_get_computed_props(Voc, Props) :-
	findall([PropLn, Value],
		(   rdf(Voc, Prop, Value, amalgame_vocs),
		    rdf_global_id(amalgame:PropLn, Prop)
		),
		GraphProps
	       ),
	maplist(=.., Props, GraphProps).

voc_clear_stats :-
	Graph = amalgame_vocs,
	(   rdf_graph(Graph)
	->  rdf_unload(amalgame_vocs)
	;   true),
	print_message(informational, map(cleared, 'vocabulary statistics', amalgame_vocs, all)).

voc_delpart :-
	findall(Voc, rdf(Voc, rdf:type, amalgame:'UnmappedConceptScheme'), Unmapped),
	findall(Voc, rdf(Voc, rdf:type, amalgame:'FullyMappedConceptScheme'), Mapped),
	append(Unmapped, Mapped, Partitioned),
	forall(member(Voc, Partitioned),
	       ( rdf_unload(Voc),
		 print_message(informational, map(cleared, 'vocabulary', Voc, all))
	       )
	      ).


%%	voc_ensure_stats(+Type) is det.
%
%	Ensures that the statistical properties of Type are asserted in
%	the amalgame graph.

voc_ensure_stats(all) :-
	findall(V, rdfs_individual_of(V, skos:'ConceptScheme'), Vocs),!,
	length(Vocs, N),
	print_message(informational, map(found, 'SKOS vocabularies (ConceptSchemes)', repository, N)),

	forall(member(V, Vocs),voc_ensure_stats(all(V))).

voc_ensure_stats(all(V)) :-
	voc_ensure_stats(numberOfConcepts(V)),
	voc_ensure_stats(numberOfPrefLabels(V)),
	voc_ensure_stats(numberOfAltLabels(V)),
	voc_ensure_stats(numberOfMappedConcepts(V)).


voc_ensure_stats(numberOfConcepts(Voc)) :-
	(   rdf(Voc,amalgame:numberOfConcepts, literal(type(_, Count)))
	->  true
	;   count_concepts(Voc, Count),
	    assert_voc_props(Voc:[numberOfConcepts(literal(type('http://www.w3.org/2001/XMLSchema#int', Count)))])
	),!.

voc_ensure_stats(numberOfPrefLabels(Voc)) :-
	(   rdf(Voc,amalgame:numberOfPrefLabels, literal(type(_, Count)))
	->  true
	;   count_prefLabels(Voc, Count),
	    assert_voc_props(Voc:[numberOfPrefLabels(literal(type('http://www.w3.org/2001/XMLSchema#int', Count)))])
	),!.

voc_ensure_stats(numberOfAltLabels(Voc)) :-
	(   rdf(Voc,amalgame:numberOfAltLabels, literal(type(_, Count)))
	->  true
	;   count_altLabels(Voc, Count),
	    assert_voc_props(Voc:[numberOfAltLabels(literal(type('http://www.w3.org/2001/XMLSchema#int', Count)))])
	),!.

voc_ensure_stats(numberOfMappedConcepts(Voc)) :-
	(   rdf(Voc,amalgame:numberOfMappedConcepts, literal(type(_, Count)))
	->  true
	;   count_mapped_concepts(Voc, Count),
	    assert_voc_props(Voc:[numberOfMappedConcepts(literal(type('http://www.w3.org/2001/XMLSchema#int', Count)))])
	),!.

assert_voc_props([]).
assert_voc_props([Head|Tail]) :-
	assert_voc_props(Head),
	assert_voc_props(Tail),!.

assert_voc_props(Voc:Props) :-
	rdf_equal(amalgame:'', NS),
	(   rdfs_individual_of(Voc, skos:'ConceptScheme')
	->  true
	;   rdf_assert(Voc, rdf:type, skos:'ConceptScheme', amalgame_vocs)
	),
	forall(member(M,Props),
	       (   M =.. [PropName, Value],
		   format(atom(URI), '~w~w', [NS,PropName]),
		   rdf_assert(Voc, URI, Value, amalgame_vocs)
	       )).

count_concepts(Voc, Count) :-
	findall(Concept,
		rdf(Concept, skos:inScheme, Voc),
		Concepts),
	length(Concepts, Count),
	print_message(informational, map(found, 'SKOS Concepts', Voc, Count)).


count_prefLabels(Voc, Count) :-
	findall(Label,
		(   rdf(Concept, skos:inScheme, Voc),
		    rdf_has(Concept, skos:prefLabel, literal(Label))
		),
		Labels),
	length(Labels, Count),
	print_message(informational, map(found, 'SKOS preferred labels', Voc, Count)).

count_altLabels(Voc, Count) :-
	findall(Label,
		(   rdf(Concept, skos:inScheme, Voc),
		    rdf_has(Concept, skos:altLabel, literal(Label))
		),
		Labels),
	length(Labels, Count),
	print_message(informational, map(found, 'SKOS alternative labels', Voc, Count)).

count_mapped_concepts(Voc, Count) :-
	findall(C,
		(   rdf(C, skos:inScheme, Voc),
		    (  	has_map_chk([C,_], _, _)
		    ;	has_map_chk([_,C], _, _)
		    )
                ),
		Concepts),
	sort(Concepts, Sorted),
	length(Sorted, Count),
	print_message(informational, map(found, 'SKOS mapped concepts', Voc, Count)).

voc_partition(Voc, [Mapped, Unmapped]) :-
	format(atom(Mapped), '~w/mapped', [Voc]),
	format(atom(Unmapped), '~w/unmapped', [Voc]),

	(   rdf_graph(Mapped) -> rdf_unload(Mapped); true),
	(   rdf_graph(Unmapped) -> rdf_unload(Unmapped); true),

	rdf_assert(Mapped,   rdf:type, amalgame:'FullyMappedConceptScheme', Mapped),
	rdf_assert(Mapped,   rdf:type, amalgame:'DerivedConceptScheme', Mapped),
	rdf_assert(Unmapped, rdf:type, amalgame:'UnmappedConceptScheme', Unmapped),
	rdf_assert(Unmapped,   rdf:type, amalgame:'DerivedConceptScheme', Unmapped),
	rdf_transaction(forall(rdf(C, skos:inScheme, Voc),
			      classify_concept(C, Mapped, Unmapped)
			     )),
	voc_ensure_stats(all(Mapped)),
	voc_ensure_stats(all(Unmapped)).


classify_concept(C, Mapped, Unmapped) :-
	(   (has_map_chk([C, _],_ ,_); has_map_chk([_,C], _, _))
	->  rdf_assert(C, skos:inScheme, Mapped, Mapped)
	;   rdf_assert(C, skos:inScheme, Unmapped, Unmapped)
	).

%%	skos_label(+Concept, -Label, -Options) is det.
%
%	Return the most appropriate Label for Concept.
%       May or may not include specified language
%      (use ISO code) (code by Victor)

skos_label(Concept, Label, Options) :-
	memberchk(preflang(PrefLang),Options),
	rdf_has(Concept, skos:prefLabel, literal(lang(PrefLang, Label))),!.
skos_label(Concept, Label, Options) :-
	memberchk(preflang(PrefLang),Options),
	rdf_has(Concept, skos:altLabel, literal(lang(PrefLang, Label))),!.

skos_label(Concept, Label, _Options) :-
	rdf_has(Concept, skos:prefLabel, literal(lang(_, Label))),!.
skos_label(Concept, Label, _Options) :-
	rdf_has(Concept, skos:altLabel, literal(lang(_, Label))),!.

skos_label(Concept, Label, _) :-
	rdfs_label(Concept, Label),!.
skos_label(Concept, Label, _) :-
	format(atom(Label), '<~p>', [Concept]),!.

% for backwards compatibility
skos_label(Concept, Label):-
	skos_label(Concept, Label, []).
