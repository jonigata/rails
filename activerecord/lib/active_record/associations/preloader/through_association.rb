module ActiveRecord
  module Associations
    class Preloader
      module ThroughAssociation #:nodoc:
        def through_reflection
          reflection.through_reflection
        end

        def source_reflection
          reflection.source_reflection
        end

        def associated_records_by_owner(preloader)
          preloader.preload(owners,
                            through_reflection.name,
                            through_scope)

          through_records = owners.map do |owner, h|
            association = owner.association through_reflection.name

            [owner, Array(association.reader)]
          end

          reset_association owners, through_reflection.name

          middle_records = through_records.map { |(_,rec)| rec }.flatten

          preloaders = preloader.preload(middle_records,
                                         source_reflection.name,
                                         reflection_scope)

          middle_to_pl = preloaders.each_with_object({}) do |pl,h|
            pl.owners.each { |middle|
              h[middle] = pl
            }
          end

          through_records.each_with_object({}) { |(lhs,center),records_by_owner|
            pl_to_middle = center.group_by { |record| middle_to_pl[record] }

            records_by_owner[lhs] = pl_to_middle.flat_map do |pl, middles|
              rhs_records = middles.flat_map { |r|
                r.send(source_reflection.name)
              }.compact

              loaded_records = pl.preloaded_records
              i = 0
              record_index = loaded_records.each_with_object({}) { |r,indexes|
                indexes[r] = i
                i += 1
              }
              records = rhs_records.sort_by { |rhs| record_index[rhs] }
              @preloaded_records.concat rhs_records
              records
            end
          }
        end

        private

        def reset_association(owners, association_name)
          should_reset = (through_scope != through_reflection.klass.unscoped) ||
             (reflection.options[:source_type] && through_reflection.collection?)

          # Dont cache the association - we would only be caching a subset
          if should_reset
            owners.each { |owner|
              owner.association(association_name).reset
            }
          end
        end


        def through_scope
          scope = through_reflection.klass.unscoped

          if options[:source_type]
            scope.where! reflection.foreign_type => options[:source_type]
          else
            unless reflection_scope.where_values.empty?
              scope.includes_values = Array(reflection_scope.values[:includes] || options[:source])
              scope.where_values    = reflection_scope.values[:where]
            end

            scope.references! reflection_scope.values[:references]
            scope.order! reflection_scope.values[:order] if scope.eager_loading?
          end

          scope
        end
      end
    end
  end
end
