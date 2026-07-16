desc "Expire policies whose coverage period has ended"
task expire_policies: :environment do
  result = ExpirePolicies.call

  puts "Expired #{result.updated_count} policy#{'ies' unless result.updated_count == 1}"
end
