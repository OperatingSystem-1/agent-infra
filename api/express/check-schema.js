const { Pool } = require('pg');

const pool = new Pool({
  connectionString: 'postgresql://neondb_owner:npg_24bYhdRcyZax@ep-polished-bread-ai1pqzi9-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require'
});

async function checkSchema() {
  const result = await pool.query(`
    SELECT column_name, data_type 
    FROM information_schema.columns 
    WHERE table_name = 'tq_messages'
    ORDER BY ordinal_position
  `);
  
  console.log('tq_messages columns:');
  result.rows.forEach(row => {
    console.log(`  ${row.column_name}: ${row.data_type}`);
  });
  
  process.exit(0);
}

checkSchema().catch(console.error);
